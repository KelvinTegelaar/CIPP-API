function Invoke-ListAndroidEnrollmentProfiles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.Read
    .DESCRIPTION
        Lists Android Enterprise enrollment profiles and hydrates token fields when Graph omits them from the list response.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Select = 'id,displayName,description,enrollmentMode,enrollmentTokenType,enrolledDeviceCount,tokenExpirationDateTime,lastModifiedDateTime,tokenValue,qrCodeContent,qrCodeImage'
    $EncodedSelect = [System.Uri]::EscapeDataString($Select)
    $BaseUri = 'https://graph.microsoft.com/beta/deviceManagement/androidDeviceOwnerEnrollmentProfiles'

    try {
        $EnrollmentProfiles = @(New-GraphGetRequest -uri "${BaseUri}?`$select=$EncodedSelect" -tenantid $TenantFilter)
        $Results = foreach ($EnrollmentProfile in $EnrollmentProfiles) {
            $ProfileObject = $EnrollmentProfile | Select-Object *
            $MissingTokenData = [string]::IsNullOrWhiteSpace($ProfileObject.tokenValue) -and
            [string]::IsNullOrWhiteSpace($ProfileObject.qrCodeContent) -and
            [string]::IsNullOrWhiteSpace($ProfileObject.qrCodeImage.value)

            if (($ProfileObject.enrollmentMode -eq 'corporateOwnedAOSPUserlessDevice' -or $ProfileObject.enrollmentMode -eq 'corporateOwnedAOSPUserAssociatedDevice') -and $MissingTokenData -and -not [string]::IsNullOrWhiteSpace($ProfileObject.id)) {
                try {
                    $ProfileDetails = New-GraphGetRequest -uri "$BaseUri/$($ProfileObject.id)?`$select=$EncodedSelect" -tenantid $TenantFilter
                    foreach ($Property in $ProfileDetails.PSObject.Properties) {
                        $ProfileObject | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to hydrate Android enrollment token fields for profile $($ProfileObject.displayName ?? $ProfileObject.id)" -Sev Warning -LogData $ErrorMessage
                }
            }

            $ProfileObject
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to list Android enrollment profiles: $($ErrorMessage.NormalizedMessage)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
