# Script: zabbix_vbr
# Author: Starikov Anton
# Email: starikov_aa@mail.ru
# GitHub: https://github.com/starikov-aa/zabbix-veeam
# Description: Query Veeam job information
# This script is intended for use with Zabbix >= 4
#
# USAGE:
#
#   as a script:    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr.ps1" <ITEM_TO_QUERY>
#   as an item:     vbr[<ITEM_TO_QUERY>]
#
# ITEMS availables (Switch) :
# - DiscoveryBackupJobs
# - DiscoveryBackupSyncJobs
# - DiscoveryUnMngAgentJobsPerMashine
# - DiscoveryUnMngAgentJobsPerPolicy
# - DiscoveryTapeJobs
# - DiscoveryRepo
# - DiscoveryBackupJobPerVM
# - DiscoveryBackupSyncJobPerVM
# - ResultBackup
# - ResultBackupSync
# - ResultUnMngAgentPerMashine
# - ResultUnMngAgentPolicy
# - ResultMngAgentPolicy
# - ResultBackupPerVM
# - ResultBackupSyncPerVM
# - RepoInfo
# - ResultTapeJob
#
# Examples:
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr.ps1" DiscoveryBackupJobs
# Return a Json Value with all Backups Name and JobID 
#
# Add to Zabbix Agent
#   UserParameter=vbr[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Zabbix Agent\scripts\zabbix_vbr_job.ps1" "$1"

# Load Veeam Module
Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue

function DiscoveryToZabbix {
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,
        [Parameter(Position = 0)]
        [String[]]$Property = @( "ID", "NAME", "JOBTYPE")
    )
	
    begin {
        $out = @()
    }
	
    process {
        if ($InputObject) {
            $InputObject | ForEach-Object {
                if ($_) {
                    $Element = @{ }
                    foreach ($P in $Property) {
                        $Element.Add("{#$($P.ToUpper())}", [String]$_.$P)
                    }
                    $out += $Element
                }
            }
        }
    }
    end {
        @{ 'data' = $out } | ConvertTo-Json -Compress
    }
}

function VeeamStatusReplace {
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline = $true)]
        $item)
    $item.replace('Failed', '0').
    replace('Warning', '1').
    replace('Success', '2').
    replace('None', '2').
    replace('idle', '3').
    replace('InProgress', '5').
    replace('Pending', '6').
    replace('Pausing', '7').
    replace('Postprocessing', '8').
    replace('Resuming', '9').
    replace('Starting', '10').
    replace('Stopped', '11').
    replace('Stopping', '12').
    replace('WaitingRepository', '13').
    replace('WaitingTape', '13').
    replace('Working', '13')

}


function ResultJobToZabbix {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $true)]
        [Object[]]$item,
        [string]$KeyFieldName = "JobId",
        [string[]]$PropertiesFieldName = @("Result"),
        [string]$Path = "jobresult"
    )

    begin {
        $out = @{ }
    }

    process {
        
        if (-Not $item.[string]$KeyFieldName) {
            return
        }

        if (-Not $out.ContainsKey([string]$item.$KeyFieldName)) {
            $out += @{[string]$item.$KeyFieldName = @{ } }
        }

        for ($i = 0; $i -le $PropertiesFieldName.Count - 1; $i++) {
            if ($item) {
                if ($item.[string]$PropertiesFieldName[$i]) {
                    $prop_val = [string]$item.[string]$PropertiesFieldName[$i]
                    if (@('result', 'lastresult', 'laststate', 'status') -match $PropertiesFieldName[$i]) {
                        $prop_val = $prop_val | VeeamStatusReplace
                    }
                    $out[[string]$item.$KeyFieldName] += @{
                        $PropertiesFieldName[$i].ToUpper() = $prop_val
                    }
                }
            }
        }     
    }

    end {
        @{ 'data' = @{ $Path = $out } } | ConvertTo-Json -Depth 10 -Compress
    }
}

function GetAllVmInJob {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $true)]
        [Object[]]$item
    )

    begin {
        $out = @()
    }

    process {
        $JobObj = $item | Get-VBRJobObject
        if ($item.JobType -eq "BackupSync") {
            $JobObj = $ALL_JOB_INFO | Where-Object Id -eq $item.LinkedJobIds | Get-VBRJobObject
        }
        $JobObj | ForEach-Object {
            $VmId = $_.Object.ObjectId
            if ($_.IsIncluded -eq "True") {
                if ($_.Object.Type -eq "VM") {
                    $out += @{ "ID" = $VmId; "Name" = $_.Name }
                }
                else {
                    $ServerObj = Get-VBRServer -Name $_.Name
                    
                    if ( @('HvServer', 'HvCluster') -match $ServerObj.Type ) {
                        $VmList = $ServerObj | Find-VBRHvEntity
                    }
                    else {
                        $VmList = $ServerObj | Find-VBRViEntity
                    }

                    $VmList | ForEach-Object {
                        if (-not ($JobObj | Where-Object Name -eq $_.Name)) {
                            $out += @{ "ID" = $_.Reference; "Name" = $_.Name }
                        }
                    }
                }
            } 
        }
    }

    end {
        $out
    }
}

function GetJobsResults {
    [CmdletBinding()]
    Param (
        [Object[]]$Jobs = $ALL_JOB_INFO,
        [String]$JobType,
        [Bool]$PerVm = $false,
        [String]$JsonPath = $ITEM
    )

    begin {
        $out = @()
        $Jobs = $Jobs | Where-Object JobType -eq $JobType

        if (-Not $PerVm) {
            $out += $Jobs.FindLastSession()
        }
        else {
            $Tasks = $Jobs.FindLastSession() | Get-VBRTaskSession
            $Jobs | ForEach-Object {
                $JobId = $_.Id
                $_ | GetAllVmInJob | ForEach-Object {
                    $VmName = $_.Name
                    $Status = ($Tasks | Where-Object { $_.Name -eq $VmName -and $_.JobSess.JobId -eq $JobId } | Select-Object Status).Status
                    if (-Not $Status) {
                        $Status = 1
                    }
                    $out += @{ "JOBID" = "$($JobId)_$($_.Id)"; "RESULT" = $Status}
                }
            }
        }
    }

    end {
        $out | ResultJobToZabbix -Path $JsonPath
    }
}

$ITEM = [string]$args[0]
try {
    $ALL_JOB_INFO = [Veeam.Backup.Core.CBackupJob]::GetAll() | Where-Object IsScheduleEnabled
}
catch {
    "$(Get-Date): $($_.Exception.Message)" | Out-File -FilePath "C:\zabbix_vbr_log.txt"
}

#$ITEM = "ResultBackup"

switch ($ITEM) {
    "DiscoveryBackupJobs" {
        $ALL_JOB_INFO | Where-Object JobType -like "Backup" | DiscoveryToZabbix
    }

    "DiscoveryBackupSyncJobs" {
        $ALL_JOB_INFO | Where-Object JobType -like "BackupSync" | DiscoveryToZabbix
    }

    "DiscoveryUnMngAgentJobsPerMashine" {
        $ALL_JOB_INFO | Where-Object JobType -match "EndpointBackup" | DiscoveryToZabbix
    }

    "DiscoveryUnMngAgentJobsPerPolicy" {
        $ALL_JOB_INFO | Where-Object JobType -match "EpAgentPolicy" | DiscoveryToZabbix

    }

    "DiscoveryMngAgentJobPerPolicy" {
        $ALL_JOB_INFO | Where-Object JobType -match "EpAgentBackup" | DiscoveryToZabbix

    }

    "DiscoveryRepo" {
        Get-VBRBackupRepository | DiscoveryToZabbix NAME
    }

    "DiscoveryTapeJobs" {
        Get-VBRTapeJob | DiscoveryToZabbix ID, NAME, TYPE
    }

    "DiscoveryBackupJobPerVM" {
        $query = @()
        $ALL_JOB_INFO | Where-Object JobType -eq "Backup" | ForEach-Object {
            $JobName = $_.Name
            $JobId = $_.Id
            $_ | GetAllVmInJob | ForEach-Object { 
                $query += @{ "JOBNAME" = $JobName;
                    "ID"               = "$($JobId)_$($_.ID)";
                    "NAME"             = $_.Name
                }
            }
        }
        $query | DiscoveryToZabbix ID, NAME, JOBNAME
    }

    "DiscoveryBackupSyncJobPerVM" {
        $query = @()
        $ALL_JOB_INFO | Where-Object JobType -like "BackupSync" | ForEach-Object {
            $JobName = $_.Name
            $JobId = $_.Id
            $_ | GetAllVmInJob | ForEach-Object { 
                $query += @{ "JOBNAME" = $JobName;
                    "ID"               = "$($JobId)_$($_.ID)";
                    "NAME"             = $_.Name
                }
            }
        }
        $query | DiscoveryToZabbix ID, NAME, JOBNAME
    }

    "ResultBackup" {
        GetJobsResults -JobType "Backup"
    }

    "ResultBackupSync" {
        GetJobsResults -JobType "BackupSync"
    }

    "ResultUnMngAgentPerMashine" {
        GetJobsResults -JobType "EndpointBackup"
    }

    "ResultUnMngAgentPolicy" {
        GetJobsResults -JobType "EpAgentPolicy"
    }

    "ResultMngAgentPolicy" {
        GetJobsResults -JobType "EpAgentBackup"
    }

    "ResultTapeJob" {
        Get-VBRTapeJob | ResultJobToZabbix -KeyFieldName Id -PropertiesFieldName LastResult, LastState -Path $ITEM
    }

    "RepoInfo" {
        $query = @()
        Get-VBRBackupRepository | ForEach-Object {
            $RepoName = $_.Name
            $query += Get-WmiObject -Class Repository -ComputerName $env:COMPUTERNAME -Namespace ROOT\VeeamBS | Where-Object Name -eq $RepoName
        }
        $query | ResultJobToZabbix -KeyFieldName Name  -PropertiesFieldName Capacity, FreeSpace -Path $ITEM
    }

    "ResultBackupPerVM" {
        GetJobsResults -JobType "Backup" -PerVm $True
    }
    "ResultBackupSyncPerVM" {
        GetJobsResults -JobType "BackupSync" -PerVm $True
    }

}
