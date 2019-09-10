# Needed Parameters for the script
Param
(
    [Parameter(Mandatory=$True, HelpMessage="Enter the Resource Group of the original VM")]
    [string] $OriginalResourceGroup,
    [Parameter(Mandatory=$True, HelpMessage="Enter the original VM name")]
    [string] $OriginalvmName,
    [Parameter(Mandatory=$True, HelpMessage="Enter the new VM name")]
    [string] $NewvmName,
    [Parameter(Mandatory=$True, HelpMessage="Enter the new availability set name")]
    [string] $NewAvailSetName,
    [Parameter(Mandatory=$True, HelpMessage="Enter the new VNet resource group")]
    [string] $NewVnetResourceGroup,
    [Parameter(Mandatory=$True, HelpMessage="Enter the new VNet name")]
    [string] $NewVNetName,
    [Parameter(Mandatory=$True, HelpMessage="Enter the new Subnet name")]
    [string] $NewSubnet,
    [Parameter(Mandatory=$True, HelpMessage="Enter Azure region")]
    [string] $Location
)

################
# SCRIPT HEADER
################

<#
    .SYNOPSIS
        Migrates an Azure VM from current VNet to a new VNet in Azure by creating a new VM in new VNet retaining the original VMs configuration and data disks.

    .DESCRIPTION
        Steps in move VM to new VNet: 
            (1) Gathers info on existing VM, VNet, and subnet.
            (2) Removes the original VM while saving all data disks and VM info.
            (3) Creates VM configuration for new VM, creates nic for new VM, and new availability set.  
            (4) Adds data disks to new VM, adds nics to new VM, adds VM to the new VNet.
            (5) Creates new VM and adds the VM to the new VNet.
        
        ***NOTE***
        The line starting with Set-AzVMOSDisk be sure to set -Linux or -Windows depending on VM OS of the original VM at the end of the line before running this script.
    
    .PARAMETER OriginalResourceGroup
        Resource Group of the original VM
    .PARAMETER OriginalvmName
        Original VM name
    .PARAMETER NewvmName
        New VM name
    .PARAMETER NewAvailSetName
        New availability set name
    .PARAMETER NewVnetResourceGroup
        New VNet resource group
    .PARAMETER NewVNetName
        New VNet name
    .PARAMETER NewSubnet
        New Subnet name
    .PARAMETER Location
        Azure region

    .EXAMPLE
      OriginalresourceGroup: RG01
      OriginalvmName: VM01
      NewvmName: VM02
      NewAvailSetName: AS02
      NewVnetResourceGroup: RG02
      NewVNetName: VNETB
      NewSubnet: Subnet1
      Location: $Location
    
    .NOTES
        Name: Vnet-to-Vnet VM migration.ps1  
        Version:       1.0
        Author:        Microsoft MVP - Steve Buchanan (www.buchatech.com)
        Creation Date: 8-21-2019
        Edits:         

    .PREREQUISITES
        PowerShell version: 5 or 7
        Modules:         For PowerShell 5 use AzureRM Module. For PowerShell 7 (Core) use AZ module.
#>

<##############################################################################################
###############################################################################################
Prompt to select use with PowerShell 5 and AzureRM Module or PowerShell 7 (Core) and AZ module.
###############################################################################################
###############################################################################################>

[int]$xMenuChoiceA = 0
while ( $xMenuChoiceA -lt 1 -or $xMenuChoiceA -gt 2 ){
Write-Host "`t`t- Select: PowerShell 5 with AzureRM module [OR] PowerShell 7 with Az module. -`n" -Fore Yellow
Write-host "1. PowerShell 5 with AzureRM module" -ForegroundColor Cyan
Write-host "2. PowerShell 7 with Az module" -ForegroundColor Cyan
[Int]$xMenuChoiceA = 
read-host "Enter option 1 or 2"
} 
Switch( $xMenuChoiceA )
{
1
{
#******************************************************************************
# PowerShell 5 and AzureRM module Begin
#******************************************************************************

##############
# AZURE LOGIN
##############

Write-Host "Log into Azure Services..."
#Azure Account Login
try {
                Login-AzureRmAccount -ErrorAction Stop
}
catch {
                # The exception lands in [Microsoft.Azure.Commands.Common.Authentication.AadAuthenticationCanceledException]
                Write-Host "User Cancelled The Authentication" -ForegroundColor Yellow
                exit
}

#Prompt to select an Azure subscription
Get-AzureRmSubscription | Out-GridView -OutputMode Single -Title "Select a subscription" | ForEach-Object {$selectedSubscriptionID = $PSItem.SubscriptionId}

# Set selected Azure subscription
Select-AzureRmSubscription -SubscriptionId $selectedSubscriptionID

########################
# GET VM & Network INFO
########################

#Get info for the VNet and subnet
    $NewVnet = Get-AzureRmVirtualNetwork -Name $NewVNetName -ResourceGroupName $NewVnetResourceGroup
    $backEndSubnet = $NewVnet.Subnets|?{$_.Name -eq $NewSubnet}
    
#Get the details of the VM to be moved to the Availablity Set
    $originalVM = Get-AzureRmVM -ResourceGroupName $OriginalResourceGroup -Name $OriginalvmName

###################
# REMOVE ORIGNAL VM
###################

#Remove the original VM
    Remove-AzureRmVM -ResourceGroupName $OriginalResourceGroup -Name $OriginalvmName    

###########################
# CREATE VM CONFIG, NIC, AS
###########################

#Create new availability set if it does not exist

    $availSet = Get-AzureRmAvailabilitySet -ResourceGroupName $NewVnetResourceGroup -Name $NewAvailSetName -ErrorAction Ignore
    if (-Not $availSet) {$availSet = New-AzureRmAvailabilitySet -Location "$Location" -Name $NewAvailSetName -ResourceGroupName $NewVnetResourceGroup -PlatformFaultDomainCount 2 -PlatformUpdateDomainCount 2 -Sku Aligned}

#Create the basic configuration for the new VM
    $newVM = New-AzureRmVMConfig -VMName $NewvmName -VMSize $originalVM.HardwareProfile.VmSize -AvailabilitySetId $availSet.Id
        
#***NOTE*** Use -Linux or -Windows at the end of this line.
 Set-AzureRmVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -Name $originalVM.StorageProfile.OsDisk.Name -Windows


#Create new NIC for new VM
    $NewNic = New-AzureRmNetworkInterface -ResourceGroupName $NewVnetResourceGroup `
      -Name "01$NewvmName" `
      -Location "$Location" `
      -SubnetId $backEndSubnet.Id

#########################
# ADD DATA DISKS AND NICS
#########################

#Add Data Disks
    foreach ($disk in $originalVM.StorageProfile.DataDisks) { Add-AzureRmVMDataDisk -VM $newVM -Name $disk.Name -ManagedDiskId $disk.ManagedDisk.Id -Caching $disk.Caching -Lun $disk.Lun -DiskSizeInGB $disk.DiskSizeGB -CreateOption Attach
    }

#Add NIC(s)
    $nicId = (Get-AzureRmNetworkInterface -ResourceGroupName "$NewVnetResourceGroup" -Name "01$NewvmName").Id
    foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {Add-AzureRmVMNetworkInterface -VM $newVM -Id $nicId}

###############
# CREATE NEW VM
###############

#Recreate the VM
    New-AzureRmVM -ResourceGroupName $NewVnetResourceGroup -Location $originalVM.Location -VM $newVM -Verbose

#******************************************************************************
# PowerShell 5 and AzureRM module End
#******************************************************************************
}
2
{
#******************************************************************************
# PowerShell 7 and Az module Begins
#******************************************************************************

##############
# AZURE LOGIN
##############

Write-Host "Log into Azure Services..."
#Azure Account Login
try {
                Connect-AzAccount -ErrorAction Stop
}
catch {
                # The exception lands in [Microsoft.Azure.Commands.Common.Authentication.AadAuthenticationCanceledException]
                Write-Host "User Cancelled The Authentication" -ForegroundColor Yellow
                exit
}

#Print list of Azure subscriptions
Get-AzSubscription 

# Set Azure Subscription ID Variable
$selectedSubscriptionID = Read-Host ' If you have multple Azure Subscriptions. Enter Azure subscription ID you want to use.'

# Set Azure subscription
Set-AzContext -SubscriptionId $selectedSubscriptionID -ErrorAction Ignore

########################
# GET VM & Network INFO
########################

#Get info for the VNet and subnet
    $NewVnet = Get-AzVirtualNetwork -Name $NewVNetName -ResourceGroupName $NewVnetResourceGroup
    $backEndSubnet = $NewVnet.Subnets|?{$_.Name -eq $NewSubnet}
    
#Get the details of the VM to be moved
    $originalVM = Get-AzVM -ResourceGroupName $OriginalResourceGroup -Name $OriginalvmName

###################
# REMOVE ORIGNAL VM
###################

#Remove the original VM
    Remove-AzVM -ResourceGroupName $OriginalResourceGroup -Name $OriginalvmName    

#################################
# CREATE NEW VM CONFIG, NIC, AS
#################################

#Create new availability set if it does not exist

    $availSet = Get-AzAvailabilitySet -ResourceGroupName $NewVnetResourceGroup -Name $NewAvailSetName -ErrorAction Ignore
    if (-Not $availSet) {$availSet = New-AzAvailabilitySet -Location "$Location" -Name $NewAvailSetName -ResourceGroupName $NewVnetResourceGroup -PlatformFaultDomainCount 2 -PlatformUpdateDomainCount 2 -Sku Aligned}

#Create the basic configuration for the new VM
    $newVM = New-AzVMConfig -VMName $NewvmName -VMSize $originalVM.HardwareProfile.VmSize -AvailabilitySetId $availSet.Id
        
#***NOTE*** Use -Linux or -Windows at the end of this line.
 Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -Name $originalVM.StorageProfile.OsDisk.Name -Windows


#Create new NIC for new VM
    $NewNic = New-AzNetworkInterface -ResourceGroupName $NewVnetResourceGroup `
      -Name "01$NewvmName" `
      -Location "$Location" `
      -SubnetId $backEndSubnet.Id

#########################
# ADD DATA DISKS AND NICS
#########################

#Add Data Disks
    foreach ($disk in $originalVM.StorageProfile.DataDisks) { Add-AzVMDataDisk -VM $newVM -Name $disk.Name -ManagedDiskId $disk.ManagedDisk.Id -Caching $disk.Caching -Lun $disk.Lun -DiskSizeInGB $disk.DiskSizeGB -CreateOption Attach
    }

#Add NIC(s)
    $nicId = (Get-AzNetworkInterface -ResourceGroupName "$NewVnetResourceGroup" -Name "01$NewvmName").Id
    foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {Add-AzVMNetworkInterface -VM $newVM -Id $nicId}

###############
# CREATE NEW VM
###############

#Recreate the VM
    New-AzVM -ResourceGroupName $NewVnetResourceGroup -Location $originalVM.Location -VM $newVM -Verbose

#******************************************************************************
# PowerShell 7 and Az module End
#******************************************************************************
}
}