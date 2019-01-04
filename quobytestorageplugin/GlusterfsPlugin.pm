package PVE::Storage::GlusterfsPlugin;

use strict;
use warnings;
use IO::File;
use File::Path;
use PVE::Tools qw(run_command);
use PVE::ProcFSTools;
use PVE::Network;
use PVE::Storage::Plugin;
use PVE::JSONSchema qw(get_standard_option);

use base qw(PVE::Storage::Plugin);

# Glusterfs helper functions

my $server_test_results = {};

my $get_active_server = sub {
    my ($scfg, $return_default_if_offline) = @_;

    my $defaultserver = $scfg->{server} ? $scfg->{server} : 'localhost';

    if ($return_default_if_offline && !defined($scfg->{server2})) {
	# avoid delays (there is no backup server anyways)
	return $defaultserver;
    }

    my $serverlist = [ $defaultserver ];
    push @$serverlist, $scfg->{server2} if $scfg->{server2};

    my $ctime = time();
    foreach my $server (@$serverlist) {
	my $stat = $server_test_results->{$server};
	return $server if $stat && $stat->{active} && (($ctime - $stat->{time}) <= 2); 
    }

    foreach my $server (@$serverlist) {
	my $status = 0;

	if ($server && $server ne 'localhost' && $server ne '127.0.0.1' && $server ne '::1') {

	    # ping the echo port (7) without service check
	    $status = PVE::Network::tcp_ping($server, undef, 2);

	} else {

	    my $parser = sub {
		my $line = shift;

		if ($line =~ m/Status: Started$/) {
		    $status = 1;
		}
	    };

	    my $cmd = ['/usr/sbin/gluster', 'volume', 'info', $scfg->{volume}];

	    run_command($cmd, errmsg => "glusterfs error", errfunc => sub {}, outfunc => $parser);
	}

	$server_test_results->{$server} = { time => time(), active => $status };
	return $server if $status;
    }

    return $defaultserver if $return_default_if_offline;

    return undef;
};

sub glusterfs_is_mounted {
    my ($volume, $mountpoint, $mountdata) = @_;

    $mountdata = PVE::ProcFSTools::parse_proc_mounts() if !$mountdata;

    return $mountpoint if grep {
	$_->[2] eq 'fuse.glusterfs' &&
	$_->[0] =~ /^\S+:\Q$volume\E$/ &&
	$_->[1] eq $mountpoint
    } @$mountdata;
    return undef;
}

sub glusterfs_mount {
    my ($server, $volume, $mountpoint) = @_;

    my $source = "$server:$volume";

    my $cmd = ['/bin/mount', '-t', 'glusterfs', $source, $mountpoint];

    run_command($cmd, errmsg => "mount error");
}

# Configuration

sub type {
    return 'glusterfs';
}

sub plugindata {
    return {
	content => [ { images => 1, vztmpl => 1, iso => 1, backup => 1},
		     { images => 1 }],
	format => [ { raw => 1, qcow2 => 1, vmdk => 1 } , 'raw' ],
    };
}

sub properties {
    return {
	volume => {
	    description => "Glusterfs Volume.",
	    type => 'string',
	},
	server2 => {
	    description => "Backup volfile server IP or DNS name.",
	    type => 'string', format => 'pve-storage-server',
	    requires => 'server',
	},
	transport => {
	    description => "Gluster transport: tcp or rdma",
	    type => 'string',
	    enum => ['tcp', 'rdma', 'unix'],
    	},
    };
}

sub options {
    return {
	path => { fixed => 1 },
	server => { optional => 1 },
	server2 => { optional => 1 },
	volume => { fixed => 1 },
	transport => { optional => 1 },
        nodes => { optional => 1 },
	disable => { optional => 1 },
        maxfiles => { optional => 1 },
	content => { optional => 1 },
	format => { optional => 1 },
	mkdir => { optional => 1 },
	bwlimit => { optional => 1 },
    };
}


sub check_config {
    my ($class, $sectionId, $config, $create, $skipSchemaCheck) = @_;

    $config->{path} = "/mnt/pve/$sectionId" if $create && !$config->{path};

    return $class->SUPER::check_config($sectionId, $config, $create, $skipSchemaCheck);
}

# Storage implementation

sub parse_name_dir {
    my $name = shift;

    if ($name =~ m!^((base-)?[^/\s]+\.(raw|qcow2|vmdk))$!) {
        return ($1, $3, $2);
    }

    die "unable to parse volume filename '$name'\n";
}

my $find_free_diskname = sub {
    my ($imgdir, $vmid, $fmt, $scfg) = @_;

    my $disk_list = [];

    my $dh = IO::Dir->new ($imgdir);
    @$disk_list = $dh->read() if defined($dh);

    return PVE::Storage::Plugin::get_next_vm_diskname($disk_list, $imgdir, $vmid, $fmt, $scfg, 1);
};

sub path {
    my ($class, $scfg, $volname, $storeid, $snapname) = @_;

    my ($vtype, $name, $vmid, undef, undef, $isBase, $format) =
	$class->parse_volname($volname);

    # Note: qcow2/qed has internal snapshot, so path is always
    # the same (with or without snapshot => same file).
    die "can't snapshot this image format\n" 
	if defined($snapname) && $format !~ m/^(qcow2|qed)$/;

    my $path = undef;
    if ($vtype eq 'images') {

	my $server = &$get_active_server($scfg, 1);
	my $glustervolume = $scfg->{volume};
	my $transport = $scfg->{transport};
	my $protocol = "gluster";

	if ($transport) {
	    $protocol = "gluster+$transport";
	}

	$path = "$protocol://$server/$glustervolume/images/$vmid/$name";

    } else {
	my $dir = $class->get_subdir($scfg, $vtype);
	$path = "$dir/$name";
    }

    return wantarray ? ($path, $vmid, $vtype) : $path;
}

sub clone_image {
    my ($class, $scfg, $storeid, $volname, $vmid, $snap) = @_;

    die "storage definintion has no path\n" if !$scfg->{path};

    my ($vtype, $basename, $basevmid, undef, undef, $isBase, $format) =
	$class->parse_volname($volname);

    die "clone_image on wrong vtype '$vtype'\n" if $vtype ne 'images';

    die "this storage type does not support clone_image on snapshot\n" if $snap;

    die "this storage type does not support clone_image on subvolumes\n" if $format eq 'subvol';

    die "clone_image only works on base images\n" if !$isBase;

    my $imagedir = $class->get_subdir($scfg, 'images');
    $imagedir .= "/$vmid";

    mkpath $imagedir;

    my $name = $find_free_diskname->($imagedir, $vmid, "qcow2", $scfg);

    warn "clone $volname: $vtype, $name, $vmid to $name (base=../$basevmid/$basename)\n";

    my $path = "$imagedir/$name";

    die "disk image '$path' already exists\n" if -e $path;

    my $server = &$get_active_server($scfg, 1);
    my $glustervolume = $scfg->{volume};
    my $volumepath = "gluster://$server/$glustervolume/images/$vmid/$name";

    my $cmd = ['/usr/bin/qemu-img', 'create', '-b', "../$basevmid/$basename",
	       '-f', 'qcow2', $volumepath];

    run_command($cmd, errmsg => "unable to create image");

    return "$basevmid/$basename/$vmid/$name";
}

sub alloc_image {
    my ($class, $storeid, $scfg, $vmid, $fmt, $name, $size) = @_;

    my $imagedir = $class->get_subdir($scfg, 'images');
    $imagedir .= "/$vmid";

    mkpath $imagedir;

    $name = $find_free_diskname->($imagedir, $vmid, $fmt, $scfg) if !$name;

    my (undef, $tmpfmt) = parse_name_dir($name);

    die "illegal name '$name' - wrong extension for format ('$tmpfmt != '$fmt')\n"
        if $tmpfmt ne $fmt;

    my $path = "$imagedir/$name";

    die "disk image '$path' already exists\n" if -e $path;

    my $server = &$get_active_server($scfg, 1);
    my $glustervolume = $scfg->{volume};
    my $volumepath = "gluster://$server/$glustervolume/images/$vmid/$name";

    my $cmd = ['/usr/bin/qemu-img', 'create'];

    push @$cmd, '-o', 'preallocation=metadata' if $fmt eq 'qcow2';

    push @$cmd, '-f', $fmt, $volumepath, "${size}K";

    run_command($cmd, errmsg => "unable to create image");

    return "$vmid/$name";
}

sub status {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
	if !$cache->{mountdata};

    my $path = $scfg->{path};

    my $volume = $scfg->{volume};

    return undef if !glusterfs_is_mounted($volume, $path, $cache->{mountdata});

    return $class->SUPER::status($storeid, $scfg, $cache);
}

sub activate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
	if !$cache->{mountdata};

    my $path = $scfg->{path};
    my $volume = $scfg->{volume};

    if (!glusterfs_is_mounted($volume, $path, $cache->{mountdata})) {
	
	mkpath $path if !(defined($scfg->{mkdir}) && !$scfg->{mkdir});

	die "unable to activate storage '$storeid' - " .
	    "directory '$path' does not exist\n" if ! -d $path;

	my $server = &$get_active_server($scfg, 1);

	glusterfs_mount($server, $volume, $path);
    }

    $class->SUPER::activate_storage($storeid, $scfg, $cache);
}

sub deactivate_storage {
    my ($class, $storeid, $scfg, $cache) = @_;

    $cache->{mountdata} = PVE::ProcFSTools::parse_proc_mounts()
	if !$cache->{mountdata};

    my $path = $scfg->{path};
    my $volume = $scfg->{volume};

    if (glusterfs_is_mounted($volume, $path, $cache->{mountdata})) {
	my $cmd = ['/bin/umount', $path];
	run_command($cmd, errmsg => 'umount error');
    }
}

sub activate_volume {
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;

    # do nothing by default
}

sub deactivate_volume {
    my ($class, $storeid, $scfg, $volname, $snapname, $cache) = @_;

    # do nothing by default
}

sub check_connection {
    my ($class, $storeid, $scfg, $cache) = @_;

    my $server = &$get_active_server($scfg);

    return defined($server) ? 1 : 0;
}

1;
