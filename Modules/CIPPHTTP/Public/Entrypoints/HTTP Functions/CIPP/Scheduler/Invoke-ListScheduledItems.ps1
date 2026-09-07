function Invoke-ListScheduledItems {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.Read
    .DESCRIPTION
        Lists scheduled tasks in CIPP, filterable by tenant or task ID. Returns task name, command, schedule, and last execution status.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $ScheduledItemFilter = [System.Collections.Generic.List[string]]::new()
    $ScheduledItemFilter.Add("PartitionKey eq 'ScheduledTask'")

    $Id = $Request.Query.Id ?? $Request.Body.Id
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    if ($Id) {
        # Interact with query parameters.
        $SafeId = ConvertTo-CIPPODataFilterValue -Value $Id -Type String
        $ScheduledItemFilter.Add("RowKey eq '$SafeId'")
    } else {
        # Interact with query parameters or the body of the request.
        # Include tasks CIPP hides from the normal task list (internal/system-scheduled work).
        $ShowHidden = ($Request.Query.ShowHidden -eq $true) -or ($Request.Body.ShowHidden -eq $true)
        $Name = $Request.Query.Name ?? $Request.Body.Name
        $Type = $Request.Query.Type ?? $Request.Body.Type
        $SearchTitle = $Request.query.SearchTitle ?? $Request.body.SearchTitle

        if ($ShowHidden) {
            $ScheduledItemFilter.Add("(Hidden eq true or Hidden eq 'True')")
        } else {
            $ScheduledItemFilter.Add("(Hidden eq false or Hidden eq 'False')")
        }

        if ($Name) {
            $SafeName = ConvertTo-CIPPODataFilterValue -Value $Name -Type String
            $ScheduledItemFilter.Add("Name eq '$SafeName'")
        }

        if ($Type) {
            $SafeType = ConvertTo-CIPPODataFilterValue -Value $Type -Type String
            $ScheduledItemFilter.Add("Command eq '$SafeType'")
        }
    }

    if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
        # Tasks are stored against whichever tenant identifier the caller supplied - customerId,
        # default domain, or the initial .onmicrosoft.com domain - so resolve the tenant up front
        # and let storage match any of them. (Get-Tenants itself accepts all three as -TenantFilter.)
        $TenantObject = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        $TenantIdentifiers = @($TenantObject.defaultDomainName, $TenantObject.initialDomainName, $TenantObject.customerId) | Where-Object { $_ } | Select-Object -Unique
        if (-not $TenantIdentifiers) {
            # Tenant could not be resolved (deleted, excluded, or not visible to the caller).
            # Fall back to the raw value so we filter on something rather than on nothing.
            $TenantIdentifiers = @($TenantFilter)
        }
        $TenantClauses = foreach ($TenantIdentifier in $TenantIdentifiers) {
            "Tenant eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $TenantIdentifier -Type String)
        }
        $ScheduledItemFilter.Add('({0})' -f ($TenantClauses -join ' or '))
    }

    $Filter = $ScheduledItemFilter -join ' and '

    Write-Host "Filter: $Filter"
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    $Tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    Write-Information "Retrieved $($Tasks.Count) scheduled tasks from storage."

    # Kept client-side: Azure Table Storage has no contains/startswith, and SearchTitle is used with
    # both leading and trailing wildcards (e.g. '*Vacation*').
    if ($SearchTitle) {
        $Tasks = $Tasks | Where-Object { $_.Name -like $SearchTitle }
    }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList

    $TenantLookup = @{}
    foreach ($Tenant in (Get-Tenants -IncludeErrors | Select-Object customerId, defaultDomainName, initialDomainName)) {
        if ($Tenant.customerId) {
            $TenantLookup[[string]$Tenant.customerId] = $Tenant
        }
    }

    if ($AllowedTenants -notcontains 'AllTenants') {
        $AllowedTenantIdentifiers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($AllowedTenant in $AllowedTenants) {
            $null = $AllowedTenantIdentifiers.Add([string]$AllowedTenant)
            if ($TenantLookup.ContainsKey([string]$AllowedTenant)) {
                # A task keyed on any of the tenant's identifiers must pass the access check, not just
                # the default domain - otherwise a scoped user cannot see their own initial-domain tasks.
                foreach ($Domain in @($TenantLookup[[string]$AllowedTenant].defaultDomainName, $TenantLookup[[string]$AllowedTenant].initialDomainName)) {
                    if ($Domain) { $null = $AllowedTenantIdentifiers.Add([string]$Domain) }
                }
            }
        }
        $Tasks = $Tasks | Where-Object { $AllowedTenantIdentifiers.Contains([string]$_.Tenant) }
    }

    Write-Information "Found $($Tasks.Count) scheduled tasks after filtering and access check."

    $ScheduledTasks = foreach ($Task in $Tasks) {
        if (!$Task.Command) {
            Write-Information "Skipping invalid scheduled task entry: $($Task.RowKey)"
            continue
        }

        if ($Task.Parameters) {
            $Task.Parameters = $Task.Parameters | ConvertFrom-Json -ErrorAction SilentlyContinue
            # Remove headers from parameters for cleaner display, and because they may contain sensitive information. Headers are only used for execution, not needed for display.
            if ($Task.Parameters.Headers) {
                $Task.Parameters.PSObject.Properties.Remove('Headers')
            }
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
            if (!$Task.Tenant) {
                $Task | Add-Member -NotePropertyName Tenant -NotePropertyValue 'None' -Force
            } else {
                $TenantValue = [string]$Task.Tenant
                if ($TenantLookup.ContainsKey($TenantValue)) {
                    $TenantValue = $TenantLookup[$TenantValue].defaultDomainName
                }
                $Task.Tenant = [PSCustomObject]@{
                    label = $TenantValue
                    value = $TenantValue
                    type  = 'Tenant'
                }
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
