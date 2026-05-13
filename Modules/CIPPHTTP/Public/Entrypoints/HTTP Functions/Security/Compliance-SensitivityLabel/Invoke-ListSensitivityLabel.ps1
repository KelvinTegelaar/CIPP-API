Function Invoke-ListSensitivityLabel {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Labels = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Label' -Compliance | Select-Object * -ExcludeProperty *odata*, *data.type*
        $Policies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-LabelPolicy' -Compliance | Select-Object * -ExcludeProperty *odata*, *data.type*

        $GraphRequest = $Labels | Select-Object *,
            @{l = 'PublishedInPolicies'; e = {
                    $labelGuid = $_.Guid
                    @($Policies | Where-Object { $_.Labels -contains $labelGuid -or $_.Labels -contains $_.ImmutableId }) | Select-Object -ExpandProperty Name
                }
            }

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
