Function Invoke-ListSensitiveInfoType {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitiveInfoType.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    $IncludeBuiltIn = ($Request.Query.IncludeBuiltIn -eq 'true' -or $Request.Query.IncludeBuiltIn -eq $true)

    try {
        $SITs = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationType' -Compliance | Select-Object * -ExcludeProperty *odata*, *data.type*

        if (-not $IncludeBuiltIn) {
            $SITs = $SITs | Where-Object { $_.Publisher -ne 'Microsoft Corporation' -and $_.Publisher -notlike 'Microsoft*' }
        }

        $StatusCode = [HttpStatusCode]::OK
        $GraphRequest = $SITs
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
