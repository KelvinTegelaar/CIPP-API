Function Invoke-ListDlpCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.DlpCompliancePolicy.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpCompliancePolicy' -Compliance | Select-Object * -ExcludeProperty *odata*, *data.type*
        $Rules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpComplianceRule' -Compliance | Select-Object * -ExcludeProperty *odata*, *data.type*
        $GraphRequest = $Policies | Select-Object *,
            @{l = 'AssociatedRules'; e = { $name = $_.Name; @($Rules | Where-Object { $_.ParentPolicyName -eq $name }) } },
            @{l = 'RuleCount'; e = { $name = $_.Name; (@($Rules | Where-Object { $_.ParentPolicyName -eq $name })).Count } }
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
