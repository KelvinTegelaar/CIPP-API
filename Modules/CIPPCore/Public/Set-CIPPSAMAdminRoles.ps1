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

    $SAMRolesTable = Get-CIPPTable -tablename 'SAMRoles'
    $Roles = Get-CIPPAzDataTableEntity @SAMRolesTable

    $SAMRoles = $Roles.Roles | ConvertFrom-Json
    $Tenants = $Roles.Tenants | ConvertFrom-Json

    if (($SAMRoles | Measure-Object).count -gt 0 -and $Tenants -contains $TenantFilter -or $Tenants -contains 'AllTenants') {
        $AppMemberOf = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($ENV:ApplicationID)')/memberOf/#microsoft.graph.directoryRole" -tenantid $TenantFilter -AsApp $true

        $sp = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($ENV:ApplicationID)')?`$select=id,displayName" -tenantid $TenantFilter -AsApp $true)
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
                $null = New-ExoRequest -cmdlet 'New-ServicePrincipal' -cmdParams @{AppId = $ENV:ApplicationID; ObjectId = $id; DisplayName = 'CIPP-SAM' } -Compliance -tenantid $TenantFilter -useSystemMailbox $true -AsApp
                $ActionLogs.Add('Added Service Principal to Compliance Center')
            } catch {
                $ActionLogs.Add('Service Principal already added to Compliance Center')
            }
            try {
                $null = New-ExoRequest -cmdlet 'New-ServicePrincipal' -cmdParams @{AppId = $ENV:ApplicationID; ObjectId = $id; DisplayName = 'CIPP-SAM' } -tenantid $TenantFilter -useSystemMailbox $true -AsApp
                $ActionLogs.Add('Added Service Principal to Exchange Online')
            } catch {
                $ActionLogs.Add('Service Principal already added to Exchange Online')
            }

            Write-Verbose ($Requests | ConvertTo-Json -Depth 5)
            $Results = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests)
            $Results | ForEach-Object {
                if ($_.status -eq 204) {
                    $ActionLogs.Add("Added service principal to directory role $($_.id)")
                } else {
                    $ActionLogs.Add("Failed to add service principal to directoryRole $($_.id)")
                    Write-Verbose ($_ | ConvertTo-Json -Depth 5)
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
