function Invoke-ListQuarantinePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.body.TenantFilter
    $QuarantinePolicyType = $Request.Query.Type ?? 'QuarantinePolicy'

    $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantinePolicy' -cmdParams @{QuarantinePolicyType=$QuarantinePolicyType} | Select-Object -Property * -ExcludeProperty *odata*, *data.type*

    if ($QuarantinePolicyType -eq 'QuarantinePolicy') {
        # Convert the string EndUserQuarantinePermissions to individual properties
        $Policies | ForEach-Object {
            $Permissions = Convert-QuarantinePermissionsValue -InputObject $_.EndUserQuarantinePermissions
            foreach ($Perm in $Permissions.GetEnumerator()) {
                $_ | Add-Member -MemberType NoteProperty -Name ($Perm.Key -replace "PermissionTo", "" ) -Value $Perm.Value
            }
        }

        # "convert" to values display in the UI and Builtin used for filtering
        $Policies = $Policies | Select-Object -Property *,
        @{ Name = 'QuarantineNotification'; Expression = { $_.ESNEnabled -eq $true ? $true : $false} },
        @{ Name = 'ReleaseActionPreference'; Expression = { $_.Release -eq $true ? "Release" : "RequestRelease"} },
        @{ Name = 'Builtin'; Expression = { $_.Guid -eq "00000000-0000-0000-0000-000000000000" ? $true : $false} }
    }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Policies)
        })
}
