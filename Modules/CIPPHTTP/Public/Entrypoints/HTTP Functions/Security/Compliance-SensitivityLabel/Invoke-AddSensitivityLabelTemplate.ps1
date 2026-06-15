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

    $AllowedFields = @(
        'Name', 'DisplayName', 'Comment', 'Tooltip', 'ParentId',
        'Disabled', 'ContentType', 'Priority',
        'EncryptionEnabled', 'EncryptionProtectionType', 'EncryptionRightsDefinitions',
        'EncryptionContentExpiredOnDateInDaysOrNever', 'EncryptionDoNotForward',
        'EncryptionEncryptOnly', 'EncryptionOfflineAccessDays',
        'EncryptionPromptUser', 'EncryptionAESKeySize',
        'ContentMarkingHeaderEnabled', 'ContentMarkingHeaderText',
        'ContentMarkingHeaderFontSize', 'ContentMarkingHeaderFontColor', 'ContentMarkingHeaderAlignment',
        'ContentMarkingFooterEnabled', 'ContentMarkingFooterText',
        'ContentMarkingFooterFontSize', 'ContentMarkingFooterFontColor', 'ContentMarkingFooterAlignment',
        'ContentMarkingFooterMargin',
        'ContentMarkingWatermarkEnabled', 'ContentMarkingWatermarkText',
        'ContentMarkingWatermarkFontSize', 'ContentMarkingWatermarkFontColor', 'ContentMarkingWatermarkLayout',
        'ApplyContentMarkingHeaderEnabled', 'ApplyContentMarkingFooterEnabled', 'ApplyWaterMarkingEnabled',
        'SiteAndGroupProtectionEnabled', 'SiteAndGroupProtectionPrivacy',
        'SiteAndGroupProtectionAllowAccessToGuestUsers',
        'SiteAndGroupProtectionAllowEmailFromGuestUsers',
        'SiteAndGroupProtectionAllowFullAccess',
        'SiteAndGroupProtectionAllowLimitedAccess',
        'SiteAndGroupProtectionBlockAccess',
        'Conditions', 'AdvancedSettings', 'Settings', 'LocaleSettings',
        'PolicyParams'
    )

    try {
        $GUID = (New-Guid).GUID

        $Source = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            [pscustomobject]$Request.Body
        }

        $Clean = Format-CIPPCompliancePolicyParams -Source $Source -AllowedFields $AllowedFields

        $Ordered = [ordered]@{
            name     = $Clean['Name'] ?? $Source.Name ?? $Source.name
            comments = $Source.Comment ?? $Source.comments
        }
        foreach ($k in $Clean.Keys) {
            if ($Ordered.Contains($k)) { continue }
            $Ordered[$k] = $Clean[$k]
        }

        $JSON = ([pscustomobject]$Ordered | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SensitivityLabelTemplate'
        }
        $Result = "Successfully created Sensitivity Label Template: $($Ordered['name']) with GUID $GUID"
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
