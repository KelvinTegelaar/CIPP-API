function Invoke-ListCustomRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'CustomRoles'

    $Body = Get-CIPPAzDataTableEntity @Table

    if (!$Body) {
        $Body = @(
            @{
                RowKey = 'No custom roles found'
            }
        )
    } else {
        $Body = foreach ($Role in $Body) {
            try {
                $Role.Permissions = $Role.Permissions | ConvertFrom-Json
            } catch {
                $Role.Permissions = ''
            }
            if ($Role.AllowedTenants) {
                try {
                    $Role.AllowedTenants = @($Role.AllowedTenants | ConvertFrom-Json)
                } catch {
                    $Role.AllowedTenants = ''
                }
            } else {
                $Role | Add-Member -NotePropertyName AllowedTenants -NotePropertyValue @() -Force
            }
            if ($Role.BlockedTenants) {
                try {
                    $Role.BlockedTenants = @($Role.BlockedTenants | ConvertFrom-Json)
                } catch {
                    $Role.BlockedTenants = ''
                }
            } else {
                $Role | Add-Member -NotePropertyName BlockedTenants -NotePropertyValue @() -Force
            }
            $Role
        }
        $Body = @($Body)
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
