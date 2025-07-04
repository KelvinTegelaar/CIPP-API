using namespace System.Net

function Invoke-ListConnectionFilter {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.ConnectionFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedConnectionFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Policies = $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($Policies)
    }
}
