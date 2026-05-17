# Role: PVE

Install Proxmox Mail Gateway

## Requirements

Supported Operating Systems:

* Debian Bullseye

## Default Variables

None.

## Example

```bash
ansible-playbook site.yml -l <INVENTORY_HOSTNAME> --tags pmg
```

## Nag removal

https://johnscs.com/remove-proxmox51-subscription-notice/

To remove the “You do not have a valid subscription for this server” popup message while logging in, run the command bellow. You’ll need to SSH to your Proxmox server or use the node console through the PVE web interface.

    If you have issues and need to revert changes please check the instructions at the bottom of this page.
    When you update your Proxmox server and the update includes the proxmox-widget-toolkit package, you’ll need to complete this modification again.
    This modification works with versions 5.1 and newer, tested up to the version shown in the title.

Run the following one line command and then clear your browser cache (depending on the browser you may need to open a new tab or restart the browser):

sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service

 
Manual Steps

Here are alternative step by step instructions so you can understand what the above command is doing:

1. Change to working directory

cd /usr/share/javascript/proxmox-widget-toolkit

2. Make a backup

cp proxmoxlib.js proxmoxlib.js.bak

3. Edit the file

nano proxmoxlib.js

4. Locate the following code
(Use ctrl+w in nano and search for “No valid subscription”)

Ext.Msg.show({

  title: gettext('No valid subscription'),

5. Replace “Ext.Msg.show” with “void”

void({ //Ext.Msg.show({

  title: gettext('No valid subscription'),

6. Restart the Proxmox web service (also be sure to clear your browser cache, depending on the browser you may need to open a new tab or restart the browser)

systemctl restart pveproxy.service

Additional Notes

You can quickly check if the change has been made:

grep -n -B 1 'No valid sub' proxmoxlib.js

You have three options to revert the changes:

    Manually edit  proxmoxlib.js to undo the changes you made
    Restore the backup file you created from the proxmox-widget-toolkit directory:
    mv proxmoxlib.js.bak proxmoxlib.js
    Reinstall the proxmox-widget-toolkit package from the repository:
    apt-get install --reinstall proxmox-widget-toolkit