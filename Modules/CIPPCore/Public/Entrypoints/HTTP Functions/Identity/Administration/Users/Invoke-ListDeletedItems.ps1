function Invoke-ListDeletedItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    $Types = @('administrativeUnit', 'application', 'externalUserProfile', 'pendingExternalUserProfile', 'user', 'group', 'servicePrincipal', 'certificateBasedAuthPki', 'certificateAuthorityDetail')
    $Requests = foreach ($Type in $Types) {
        [PSCustomObject]@{
            id     = $Type
            url    = "directory/deletedItems/microsoft.graph.$($Type)"
            method = 'GET'
        }
    }

    $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter

    $GraphRequest = foreach ($Type in $Types) {
        # pretty format the type name
        $FormattedType = (Get-Culture).TextInfo.ToTitleCase(($Type -creplace '([A-Z])', ' $1').Trim())

        $Result = $BulkResults | Where-Object { $_.id -eq $Type }
        if ($Result.status -eq 200) {
            $Result.body.value | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'TargetType' -NotePropertyValue $FormattedType
                $_
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })
}
