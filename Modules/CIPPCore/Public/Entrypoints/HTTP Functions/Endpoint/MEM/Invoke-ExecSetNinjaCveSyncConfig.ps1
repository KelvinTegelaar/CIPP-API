function Invoke-ExecSetNinjaCveSyncConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    
    try {
        # Get current extension config
        $ConfigTable = Get-CIPPTable -TableName 'Extensionsconfig'
        $ConfigEntity = Get-CIPPAzDataTableEntity @ConfigTable
        
        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            throw "No extension configuration found. Please configure extensions first."
        }
        
        # Parse existing config
        $Config = $ConfigEntity.config | ConvertFrom-Json
        
        # Update NinjaCveSync settings
        $NinjaCveSyncConfig = @{
            Enabled = [bool]$Request.Body.Enabled
            ScanGroupPrefix = [string]$Request.Body.ScanGroupPrefix
            RecurrenceHours = if ($Request.Body.RecurrenceHours) { [int]$Request.Body.RecurrenceHours } else { 24 }
        }
        
        # Add/update in config
        $Config | Add-Member -MemberType NoteProperty -Name 'NinjaCveSync' -Value $NinjaCveSyncConfig -Force
        
        # Save back to table
        $ConfigEntity.config = ($Config | ConvertTo-Json -Compress -Depth 10)
        Add-CIPPAzDataTableEntity @ConfigTable -Entity $ConfigEntity -Force
        
        Write-LogMessage -API $APIName -message "Saved NinjaOne CVE Sync configuration" -Sev 'Info'
        
        # Now manage the scheduled task
        $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        $TaskTable = Get-CIPPTable -TableName 'ScheduledTasks'
        
        if ($NinjaCveSyncConfig.Enabled -eq $true) {
            # Validate NinjaOne is configured
            if (-not $Config.NinjaOne -or -not $Config.NinjaOne.Instance) {
                throw "NinjaOne extension must be configured before enabling CVE sync"
            }
            
            # Remove existing task if present
            $ExistingTask = Get-CIPPAzDataTableEntity @TaskTable -Filter "Name eq 'Automated NinjaOne CVE Sync'"
            if ($ExistingTask) {
                foreach ($Task in $ExistingTask) {
                    Remove-AzDataTableEntity -Force @TaskTable -Entity $Task | Out-Null
                }
                Write-LogMessage -API $APIName -message "Removed existing NinjaOne CVE Sync scheduled task" -Sev 'Info'
            }
            
            # Create new scheduled task
            $TaskBody = [pscustomobject]@{
                TenantFilter  = 'AllTenants'
                Name          = 'Automated NinjaOne CVE Sync'
                Command       = @{
                    value = 'Invoke-CIPPScheduledNinjaCveSync'
                    label = 'Invoke-CIPPScheduledNinjaCveSync'
                }
                Parameters    = [pscustomobject]@{}  # Config read from Extensionsconfig
                ScheduledTime = $unixtime
                Recurrence    = "$($NinjaCveSyncConfig.RecurrenceHours)h"
            }
            
            Add-CIPPScheduledTask -Task $TaskBody -hidden $false -DisallowDuplicateName $true
            
            Write-LogMessage -API $APIName -message "Created NinjaOne CVE Sync scheduled task (runs every $($NinjaCveSyncConfig.RecurrenceHours) hours)" -Sev 'Info'
            
            $Result = @{ 
                'Results' = "Configuration saved and scheduled task created. CVE sync will run every $($NinjaCveSyncConfig.RecurrenceHours) hours for all tenants."
            }
            
        } else {
            # Remove scheduled task
            $ExistingTask = Get-CIPPAzDataTableEntity @TaskTable -Filter "Name eq 'Automated NinjaOne CVE Sync'"
            
            if ($ExistingTask) {
                foreach ($Task in $ExistingTask) {
                    Remove-AzDataTableEntity -Force @TaskTable -Entity $Task | Out-Null
                }
                Write-LogMessage -API $APIName -message "Removed NinjaOne CVE Sync scheduled task" -Sev 'Info'
                $Result = @{ 'Results' = 'Configuration saved and scheduled task removed' }
            } else {
                $Result = @{ 'Results' = 'Configuration saved (no existing scheduled task found)' }
            }
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Failed to save NinjaOne CVE Sync configuration: $($_.Exception.Message)" -Sev Error -LogData $ErrorMessage
        
        $Result = @{ 'Results' = "Failed: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Result
        })
}
