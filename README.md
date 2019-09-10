# Azure-VM-VNet-to-VNet-Migration-Script

.SYNOPSIS
   Migrates an Azure VM from current VNet to a new VNet in Azure by creating a new VM in new VNet retaining the original VMs configuration and data disks.

.DESCRIPTION
        Steps in move VM to new VNet:
        
           - Gathers info on existing VM, VNet, and subnet.
           - Removes the original VM while saving all data disks and VM info.
           - Creates VM configuration for new VM, creates nic for new VM, and new availability set.  
           - Adds data disks to new VM, adds nics to new VM, adds VM to the new VNet.
           - Creates new VM and adds the VM to the new VNet.
            
Full blog post about the script here: http://www.buchatech.com/2019/09/azure-vm-vnet-to-vnet-migration-script/

If you enhance the script please share back to the community through a branch.
