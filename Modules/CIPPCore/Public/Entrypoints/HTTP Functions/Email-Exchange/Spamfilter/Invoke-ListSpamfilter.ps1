using namespace System.Net

function Invoke-ListSpamfilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedContentFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
        $RuleState = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedContentFilterRule' | Select-Object * -ExcludeProperty *odata*, *data.type*
        $GraphRequest = $Policies | Select-Object *, @{l = 'ruleState'; e = { $name = $_.name; ($RuleState | Where-Object name -EQ $name).State } }, @{l = 'rulePrio'; e = { $name = $_.name; ($RuleState | Where-Object name -EQ $name).Priority } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
