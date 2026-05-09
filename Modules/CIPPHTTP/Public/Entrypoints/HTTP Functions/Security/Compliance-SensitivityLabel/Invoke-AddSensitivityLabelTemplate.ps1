Function Invoke-AddSensitivityLabelTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $GUID = (New-Guid).GUID
        $JSON = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            ([pscustomobject]$Request.Body | Select-Object Name, DisplayName, Comment, Tooltip, ParentId, ContentType, EncryptionEnabled, EncryptionProtectionType, EncryptionRightsDefinitions, EncryptionContentExpiredOnDateInDaysOrNever, EncryptionDoNotForward, EncryptionEncryptOnly, EncryptionOfflineAccessDays, EncryptionPromptUser, EncryptionAESKeySize, ContentMarkingHeaderEnabled, ContentMarkingHeaderText, ContentMarkingHeaderFontSize, ContentMarkingHeaderFontColor, ContentMarkingHeaderAlignment, ContentMarkingFooterEnabled, ContentMarkingFooterText, ContentMarkingFooterFontSize, ContentMarkingFooterFontColor, ContentMarkingFooterAlignment, ContentMarkingWatermarkEnabled, ContentMarkingWatermarkText, ContentMarkingWatermarkFontSize, ContentMarkingWatermarkFontColor, ContentMarkingWatermarkLayout, ApplyContentMarkingHeaderEnabled, ApplyContentMarkingFooterEnabled, ApplyWaterMarkingEnabled, SiteAndGroupProtectionEnabled, SiteAndGroupProtectionPrivacy, SiteAndGroupProtectionAllowAccessToGuestUsers, SiteAndGroupProtectionAllowEmailFromGuestUsers, SiteAndGroupProtectionAllowFullAccess, SiteAndGroupProtectionAllowLimitedAccess, SiteAndGroupProtectionBlockAccess, Conditions, AdvancedSettings, PolicyParams) | ForEach-Object {
                $NonEmptyProperties = $_.PSObject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                $_ | Select-Object -Property $NonEmptyProperties
            }
        }

        $JSON = ($JSON | Select-Object @{n = 'name'; e = { $_.Name ?? $_.name } }, @{n = 'comments'; e = { $_.Comment ?? $_.comments } }, * | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SensitivityLabelTemplate'
        }
        $Result = "Successfully created Sensitivity Label Template: $($Request.Body.Name ?? $Request.Body.name) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Sensitivity Label Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
