function Invoke-ListScheduledItems {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $ScheduledItemFilter = [System.Collections.Generic.List[string]]::new()
    $ScheduledItemFilter.Add("PartitionKey eq 'ScheduledTask'")

    $Id = $Request.Query.Id ?? $Request.Body.Id
    if ($Id) {
        # Interact with query parameters.
        $ScheduledItemFilter.Add("RowKey eq '$($Id)'")
    } else {
        # Interact with query parameters or the body of the request.
        $ShowHidden = $Request.Query.ShowHidden ?? $Request.Body.ShowHidden
        $Name = $Request.Query.Name ?? $Request.Body.Name
        $Type = $Request.Query.Type ?? $Request.Body.Type

        if ($ShowHidden -eq $true) {
            $ScheduledItemFilter.Add('Hidden eq true')
        } else {
            $ScheduledItemFilter.Add('Hidden eq false')
        }

        if ($Name) {
            $ScheduledItemFilter.Add("Name eq '$($Name)'")
        }

    }

    $Filter = $ScheduledItemFilter -join ' and '

    Write-Host "Filter: $Filter"
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    if ($ShowHidden -eq $true) {
        $HiddenTasks = $false
    } else {
        $HiddenTasks = $true
    }
    $Tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if ($Type) {
        $Tasks = $Tasks | Where-Object { $_.command -eq $Type }
    }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList

    if ($AllowedTenants -notcontains 'AllTenants') {
        $TenantList = Get-Tenants -IncludeErrors | Select-Object customerId, defaultDomainName
        $AllowedTenantDomains = $TenantList | Where-Object -Property customerId -In $AllowedTenants | Select-Object -ExpandProperty defaultDomainName
        $Tasks = $Tasks | Where-Object -Property Tenant -In $AllowedTenantDomains
    }
    $ScheduledTasks = foreach ($Task in $tasks) {
        if (!$Task.Tenant -or !$Task.Command) {
            continue
        }

        if ($Task.Parameters) {
            $Task.Parameters = $Task.Parameters | ConvertFrom-Json -ErrorAction SilentlyContinue
        } else {
            $Task | Add-Member -NotePropertyName Parameters -NotePropertyValue @{}
        }
        if (!$Task.Recurrence) {
            $Task | Add-Member -NotePropertyName Recurrence -NotePropertyValue 'Once' -Force
        } elseif ($Task.Recurrence -eq 0 -or [string]::IsNullOrEmpty($Task.Recurrence)) {
            $Task.Recurrence = 'Once'
        }
        try {
            $Task.ExecutedTime = [DateTimeOffset]::FromUnixTimeSeconds($Task.ExecutedTime).UtcDateTime
        } catch {}
        try {
            $Task.ScheduledTime = [DateTimeOffset]::FromUnixTimeSeconds($Task.ScheduledTime).UtcDateTime
        } catch {}

        # Handle tenant group display information
        if ($Task.TenantGroup) {
            try {
                $TenantGroupObject = $Task.TenantGroup | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($TenantGroupObject) {
                    # Create a tenant group object for the frontend formatting
                    $TenantGroupForDisplay = [PSCustomObject]@{
                        label = $TenantGroupObject.label
                        value = $TenantGroupObject.value
                        type  = 'Group'
                    }
                    $Task | Add-Member -NotePropertyName TenantGroupInfo -NotePropertyValue $TenantGroupForDisplay -Force
                    # Update the tenant to show the group object for proper formatting
                    $Task.Tenant = $TenantGroupForDisplay
                }
            } catch {
                Write-Warning "Failed to parse tenant group information for task $($Task.RowKey): $($_.Exception.Message)"
                # Fall back to keeping original tenant value
            }
        } else {
            $Task.Tenant = [PSCustomObject]@{
                label = $Task.Tenant
                value = $Task.Tenant
                type  = 'Tenant'
            }
        }
        if ($Task.Trigger) {
            try {
                $TriggerObject = $Task.Trigger | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($TriggerObject) {
                    $Task | Add-Member -NotePropertyName Trigger -NotePropertyValue $TriggerObject -Force
                }
            } catch {
                Write-Warning "Failed to parse trigger information for task $($Task.RowKey): $($_.Exception.Message)"
                # Fall back to keeping original trigger value
            }
        }

        $Task
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ScheduledTasks | Sort-Object -Property ScheduledTime, ExecutedTime -Descending)
        })

}
