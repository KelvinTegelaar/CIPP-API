Function Invoke-ListRetentionCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionCompliancePolicy' -Compliance -AsApp | Select-Object * -ExcludeProperty *odata*, *data.type*
        $Rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionComplianceRule' -Compliance -AsApp | Select-Object * -ExcludeProperty *odata*, *data.type*
        $GraphRequest = $Policies | Select-Object *,
            @{l = 'AssociatedRules'; e = { $name = $_.Name; @($Rules | Where-Object { $_.Policy -eq $name }) } },
            @{l = 'RuleCount'; e = { $name = $_.Name; (@($Rules | Where-Object { $_.Policy -eq $name })).Count } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
