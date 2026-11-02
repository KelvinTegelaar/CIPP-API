function Set-CIPPSAMAdminRoles {
    <#
    .SYNOPSIS
        Set SAM roles
    .DESCRIPTION
        Set SAM roles on a tenant
    .PARAMETER TenantFilter
        Tenant to apply the SAM roles to
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $ActionLogs = [System.Collections.Generic.List[object]]::new()

    # Default roles always assigned for all tenants
    $DefaultRoles = @(
        [PSCustomObject]@{ value = '17315797-102d-40b4-93e0-432062caca18'; label = 'Compliance Administrator' }
    )

    $SAMRolesTable = Get-CIPPTable -tablename 'SAMRoles'
    $Roles = Get-CIPPAzDataTableEntity @SAMRolesTable

    try {
        $SAMRoles = @($Roles.Roles | ConvertFrom-Json -ErrorAction Stop)
        $Tenants = $Roles.Tenants | ConvertFrom-Json -ErrorAction Stop
        if ($Tenants.value) {
            $Tenants = $Tenants.value
        }
    } catch {
        $SAMRoles = @()
        $Tenants = @()
    }

    # Merge default roles with user-configured roles, avoiding duplicates
    $ExistingValues = @($SAMRoles | ForEach-Object { $_.value })
    foreach ($DefaultRole in $DefaultRoles) {
        if ($DefaultRole.value -notin $ExistingValues) {
            $SAMRoles = @($SAMRoles) + @($DefaultRole)
        }
    }

    if (($SAMRoles | Measure-Object).Count -gt 0 -and ($Tenants -contains $TenantFilter -or $Tenants -contains 'AllTenants' -or ($Tenants | Measure-Object).Count -eq 0)) {
        $InitialRequests = @(
            [PSCustomObject]@{
                id     = 'memberOf'
                method = 'GET'
                url    = "servicePrincipals(appId='$($env:ApplicationID)')/memberOf/#microsoft.graph.directoryRole"
            }
            [PSCustomObject]@{
                id     = 'sp'
                method = 'GET'
                url    = "servicePrincipals(appId='$($env:ApplicationID)')?`$select=id,displayName"
            }
        )
        $InitialResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests $InitialRequests -AsApp $true -NoAuthCheck $true
        $AppMemberOf = ($InitialResults | Where-Object { $_.id -eq 'memberOf' }).body.value
        $sp = ($InitialResults | Where-Object { $_.id -eq 'sp' }).body
        $id = $sp.id

        $Requests = $SAMRoles | Where-Object { $AppMemberOf.roleTemplateId -notcontains $_.value } | ForEach-Object {
            # Batch add service principal to directoryRole
            [PSCustomObject]@{
                'id'      = $_.label
                'headers' = @{
                    'Content-Type' = 'application/json'
                }
                'url'     = "directoryRoles(roleTemplateId='$($_.value)')/members/`$ref"
                'method'  = 'POST'
                'body'    = @{
                    '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($id)"
                }
            }
        }
        if (($Requests | Measure-Object).count -gt 0) {
            $HasFailures = $false
            try {
                $null = New-ExoRequest -cmdlet 'New-ServicePrincipal' -cmdParams @{AppId = $env:ApplicationID; ObjectId = $id; DisplayName = 'CIPP-SAM' } -Compliance -tenantid $TenantFilter -useSystemMailbox $true -AsApp
                $ActionLogs.Add('Added Service Principal to Compliance Center')
            } catch {
                $SpError = $_.Exception.Message
                switch ($SpError) {
                    { $_ -match 'already exist' } { $ActionLogs.Add('Service Principal already added to Compliance Center') }
                    { $_ -match 'New-ServicePrincipal is not present' } { $ActionLogs.Add('Tenant does not have a license to use Compliance Center features. Skipping.') }
                    default { $ActionLogs.Add("Failed to add Service Principal to Compliance Center: $SpError"); $HasFailures = $true }
                }

            }
            try {
                $null = New-ExoRequest -cmdlet 'New-ServicePrincipal' -cmdParams @{AppId = $env:ApplicationID; ObjectId = $id; DisplayName = 'CIPP-SAM' } -tenantid $TenantFilter -useSystemMailbox $true -AsApp
                $ActionLogs.Add('Added Service Principal to Exchange Online')
            } catch {
                $SpError = $_.Exception.Message
                switch ($SpError) {
                    { $_ -match 'already exist' } { $ActionLogs.Add('Service Principal already added to Compliance Center') }
                    { $_ -match 'Response status code does not indicate success' } { $ActionLogs.Add('Could not connect to Exchange, we received an access denied. This is expected if you do not have an exchange license.'); $HasFailures = $true }
                    default { $ActionLogs.Add("Failed to add Service Principal to Compliance Center: $SpError"); $HasFailures = $true }
                }
            }

            Write-Verbose ($Requests | ConvertTo-Json -Depth 5)
            $Results = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests)
            $MissingRoles = [System.Collections.Generic.List[object]]::new()
            foreach ($Result in $Results) {
                if ($Result.status -eq 204) {
                    $ActionLogs.Add("Added service principal to directory role $($Result.id)")
                } elseif ($Result.status -eq 404) {
                    # 404 means the role template was never activated in this tenant
                    $Role = $SAMRoles | Where-Object { $_.label -eq $Result.id } | Select-Object -First 1
                    if ($Role) { $MissingRoles.Add($Role) }
                } else {
                    $ActionLogs.Add("Failed to add service principal to directoryRole $($Result.id):  $($Result | ConvertTo-Json -Depth 5)")
                    Write-Verbose ($Result | ConvertTo-Json -Depth 5)
                    $HasFailures = $true
                }
            }
            foreach ($Role in $MissingRoles) {
                try {
                    $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/directoryRoles' -tenantid $TenantFilter -body (@{ roleTemplateId = $Role.value } | ConvertTo-Json -Compress)
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles(roleTemplateId='$($Role.value)')/members/`$ref" -tenantid $TenantFilter -body (@{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($id)" } | ConvertTo-Json -Compress)
                    $ActionLogs.Add("Activated directory role $($Role.label) from its template and added service principal")
                } catch {
                    $ActionLogs.Add("Failed to activate directory role $($Role.label): $($_.Exception.Message)")
                    $HasFailures = $true
                }
            }
            $LogMessage = @{
                'API'      = 'Set-CIPPSAMAdminRoles'
                'tenant'   = $TenantFilter
                'tenantid' = (Get-Tenants -TenantFilter $TenantFilter -IncludeErrors).custom
                'message'  = ''
                'LogData'  = $ActionLogs
            }
            if ($HasFailures) {
                $LogMessage.message = 'Errors occurred while setting Admin Roles for CIPP-SAM'
                $LogMessage.sev = 'Error'
            } else {
                $LogMessage.message = 'Successfully set Admin Roles for CIPP-SAM'
                $LogMessage.sev = 'Info'
            }
            Write-LogMessage @LogMessage
        } else {
            $ActionLogs.Add('Service principal already exists in all requested Admin Roles')
        }
    } else {
        $ActionLogs.Add('No SAM roles found or tenant not added to CIPP-SAM roles')
    }
    $ActionLogs
}
