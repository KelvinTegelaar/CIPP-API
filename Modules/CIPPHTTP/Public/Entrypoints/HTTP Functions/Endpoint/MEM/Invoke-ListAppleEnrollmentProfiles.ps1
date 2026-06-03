function Invoke-ListAppleEnrollmentProfiles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.Read
    .DESCRIPTION
        Lists Apple Automated Device Enrollment tokens and enrollment profiles.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        $DepOnboardingSettings = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter)
        $Tokens = foreach ($DepSetting in $DepOnboardingSettings) {
            $Token = $DepSetting | Select-Object *
            $Token | Add-Member -NotePropertyName 'daysUntilExpiration' -NotePropertyValue $(
                if ($Token.tokenExpirationDateTime) {
                    [math]::Floor(([datetime]$Token.tokenExpirationDateTime - [datetime]::UtcNow).TotalDays)
                } else {
                    $null
                }
            ) -Force
            $Token | Add-Member -NotePropertyName 'isExpired' -NotePropertyValue $(
                if ($Token.tokenExpirationDateTime) { ([datetime]$Token.tokenExpirationDateTime) -lt [datetime]::UtcNow } else { $false }
            ) -Force
            $Token
        }

        $Profiles = foreach ($DepSetting in $DepOnboardingSettings) {
            if ([string]::IsNullOrWhiteSpace($DepSetting.id)) { continue }

            try {
                $EnrollmentProfiles = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings/$($DepSetting.id)/enrollmentProfiles" -tenantid $TenantFilter)
                foreach ($EnrollmentProfile in $EnrollmentProfiles) {
                    $ProfileType = $EnrollmentProfile.'@odata.type'
                    $Platform = switch -Regex ($ProfileType) {
                        'depMacOSEnrollmentProfile' { 'macOS'; break }
                        'depIOSEnrollmentProfile' { 'iOS/iPadOS'; break }
                        'depVisionOSEnrollmentProfile' { 'visionOS'; break }
                        'depTvOSEnrollmentProfile' { 'tvOS'; break }
                        default { 'Unknown' }
                    }

                    $ProfileObject = $EnrollmentProfile | Select-Object *
                    $ProfileObject | Add-Member -NotePropertyName 'platform' -NotePropertyValue $Platform -Force
                    $ProfileObject | Add-Member -NotePropertyName 'profileType' -NotePropertyValue 'apple' -Force
                    $ProfileObject | Add-Member -NotePropertyName 'tokenId' -NotePropertyValue $DepSetting.id -Force
                    $ProfileObject | Add-Member -NotePropertyName 'tokenName' -NotePropertyValue $DepSetting.tokenName -Force
                    $ProfileObject | Add-Member -NotePropertyName 'appleIdentifier' -NotePropertyValue $DepSetting.appleIdentifier -Force
                    $ProfileObject | Add-Member -NotePropertyName 'tokenExpirationDateTime' -NotePropertyValue $DepSetting.tokenExpirationDateTime -Force
                    $ProfileObject | Add-Member -NotePropertyName 'tokenType' -NotePropertyValue $DepSetting.tokenType -Force
                    $ProfileObject
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to list Apple ADE profiles for token $($DepSetting.tokenName)" -Sev Warning -LogData $ErrorMessage
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @{
            Results = @{
                Tokens   = @($Tokens)
                Profiles = @($Profiles)
            }
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to list Apple ADE enrollment profiles: $($ErrorMessage.NormalizedMessage)" }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Body.Results -Sev Error -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
