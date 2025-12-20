function Invoke-ExecTimeSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Subscription = Get-CIPPAzFunctionAppSubId
        $Owner = $env:WEBSITE_OWNER_NAME

        if ($env:WEBSITE_SKU -ne 'FlexConsumption' -and $Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
            $RGName = $Matches.RGName
        } else {
            $RGName = $env:WEBSITE_RESOURCE_GROUP
        }

        $FunctionName = $env:WEBSITE_SITE_NAME
        $Timezone = $Request.Body.Timezone.value ?? $Request.Body.Timezone
        $BusinessHoursStart = $Request.Body.BusinessHoursStart.value ?? $Request.Body.BusinessHoursStart

        # Validate timezone format
        if (-not $Timezone) {
            throw 'Timezone is required'
        }

        if (!$IsLinux) {
            # Get Timezone standard name for Windows
            $Timezone = Get-TimeZone -Id $Timezone | Select-Object -ExpandProperty StandardName
        }

        # Calculate business hours end time (10 hours after start)
        $BusinessHoursEnd = $null
        if ($env:WEBSITE_SKU -eq 'FlexConsumption') {
            if (-not $BusinessHoursStart) {
                throw 'Business hours start time is required for Flex Consumption plans'
            }

            # Validate time format (HH:mm)
            if ($BusinessHoursStart -notmatch '^\d{2}:\d{2}$') {
                throw 'Business hours start time must be in HH:mm format'
            }

            # Calculate end time (start + 10 hours)
            $StartTime = [DateTime]::ParseExact($BusinessHoursStart, 'HH:mm', $null)
            $EndTime = $StartTime.AddHours(10)
            $BusinessHoursEnd = $EndTime.ToString('HH:mm')
        }

        Write-Information "Updating function app time settings: Timezone=$Timezone, BusinessHoursStart=$BusinessHoursStart, BusinessHoursEnd=$BusinessHoursEnd"

        # Build app settings hashtable
        $AppSettings = @{
            'WEBSITE_TIME_ZONE' = $Timezone
        }

        if ($env:WEBSITE_SKU -eq 'FlexConsumption') {
            $AppSettings['CIPP_BUSINESS_HOURS_START'] = $BusinessHoursStart
            $AppSettings['CIPP_BUSINESS_HOURS_END'] = $BusinessHoursEnd
        }

        # Update app settings using ARM REST via managed identity
        Update-CIPPAzFunctionAppSetting -Name $FunctionName -ResourceGroupName $RGName -AppSetting $AppSettings | Out-Null

        Write-LogMessage -API 'ExecTimeSettings' -headers $Request.Headers -message "Updated time settings: Timezone=$Timezone, BusinessHours=$BusinessHoursStart-$BusinessHoursEnd" -Sev 'Info'

        $Results = @{
            Results  = 'Time settings updated successfully. Please note that timezone changes may require a function app restart to take effect.'
            Timezone = $Timezone
            SKU      = $env:WEBSITE_SKU
        }

        if ($env:WEBSITE_SKU -eq 'FlexConsumption') {
            $Results.BusinessHoursStart = $BusinessHoursStart
            $Results.BusinessHoursEnd = $BusinessHoursEnd
        }

        return ([HttpResponseContext]@{
                StatusCode = [httpstatusCode]::OK
                Body       = $Results
            })

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ExecTimeSettings' -headers $Request.Headers -message "Failed to update time settings: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage

        return ([HttpResponseContext]@{
                StatusCode = [httpstatusCode]::BadRequest
                Body       = @{
                    Results = "Failed to update time settings: $($ErrorMessage.NormalizedError)"
                }
            })
    }
}
