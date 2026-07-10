Function Invoke-ListSensitivityLabel {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.Read
    .DESCRIPTION
        Lists sensitivity labels and label policies configured in the Security & Compliance Center for a tenant.
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
            },
            @{l = 'Color'; e = {
                    # The 'color' advanced setting is only exposed inside the read-only Settings array,
                    # either as a {Key, Value} object or as the serialized string '[color, #RRGGBB]'.
                    foreach ($Entry in @($_.Settings)) {
                        if ($null -eq $Entry) { continue }
                        if ($Entry -isnot [string] -and $Entry.PSObject.Properties['Key']) {
                            if ("$($Entry.Key)" -eq 'color') { "$($Entry.Value)"; break }
                        } elseif ("$Entry" -match '^\[\s*color\s*,\s*(.*?)\s*\]$') {
                            $Matches[1]; break
                        }
                    }
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
