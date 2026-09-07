function Invoke-AddPIMRoleSettingsTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Role.ReadWrite
    .SYNOPSIS
        Create or update a PIM role settings template.
    .DESCRIPTION
        Saves a Privileged Identity Management role settings template. The settings are validated against CIPP's secure floor (activation must expire within 24 hours and require MFA or an authentication context plus a justification; eligibilities and active assignments must expire within a year; active assignments must require a justification). A template below the floor is rejected with the list of problems rather than silently adjusted. Pass GUID to update an existing template. Pass captureRoleId with a tenantFilter to build the settings from that role's current PIM policy in the tenant instead of supplying them: values below the secure floor are raised to the closest value the floor allows and every raise is reported in the results.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        # Existing template GUID when editing.
        $GUID = $Request.Body.GUID
        $TemplateName = "$($Request.Body.templateName)".Trim()
        $Description = "$($Request.Body.description)".Trim()
        # PrivilegedRoles | AllRoles | Custom
        $RoleScope = $Request.Body.roleScope.value ?? $Request.Body.roleScope
        # Roles (label/value pairs of role template ids) when roleScope is Custom.
        $Roles = @($Request.Body.roles | ForEach-Object {
                if ($null -eq $_) { return }
                $Value = $_.value ?? $_
                $Label = $_.label ?? $_.value ?? $_
                if ([string]::IsNullOrWhiteSpace("$Value")) { return }
                @{ label = "$Label"; value = "$Value" }
            })

        if ([string]::IsNullOrWhiteSpace($TemplateName)) { throw 'templateName is required' }

        # Capture mode: build the settings from a role's current PIM policy in a tenant.
        $CaptureRoleId = $Request.Body.captureRoleId.value ?? $Request.Body.captureRoleId
        $Adjustments = @()
        if (-not [string]::IsNullOrWhiteSpace("$CaptureRoleId")) {
            $CaptureTenant = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
            if ([string]::IsNullOrWhiteSpace("$CaptureTenant") -or "$CaptureTenant" -eq 'AllTenants') { throw 'A single tenantFilter is required when capturing settings from a role.' }
            $Policy = @(Get-CIPPPIMRolePolicies -TenantFilter $CaptureTenant) | Where-Object { $_.RoleDefinitionId -eq $CaptureRoleId } | Select-Object -First 1
            if (-not $Policy) { throw "No PIM role management policy was found for role $CaptureRoleId in $CaptureTenant. Privileged Identity Management may not be onboarded there yet." }
            $Captured = ConvertFrom-CIPPPIMPolicyRules -Rules $Policy.Rules
            # A tenant's live policy may sit below the floor (Entra's defaults do); a template must
            # never store that, so offending values are raised and each raise is reported.
            $Repair = Repair-CIPPPIMRoleSettingsFloor -Settings $Captured
            $SettingsInput = $Repair.Settings
            $Adjustments = @($Repair.Adjustments)

            $CaptureRoleName = "$($Request.Body.captureRoleName)".Trim()
            if ([string]::IsNullOrWhiteSpace($CaptureRoleName)) { $CaptureRoleName = "$CaptureRoleId" }
            if ([string]::IsNullOrWhiteSpace($RoleScope)) {
                $RoleScope = 'Custom'
                $Roles = @(@{ label = $CaptureRoleName; value = "$CaptureRoleId" })
            }
            if ([string]::IsNullOrWhiteSpace($Description)) { $Description = "Captured from the $CaptureRoleName role in $CaptureTenant." }
        } else {
            $SettingsInput = $Request.Body.settings
        }

        if ([string]::IsNullOrWhiteSpace($RoleScope)) { $RoleScope = 'PrivilegedRoles' }
        if ($RoleScope -notin @('PrivilegedRoles', 'AllRoles', 'Custom')) { throw "roleScope '$RoleScope' is not valid. Use PrivilegedRoles, AllRoles or Custom." }
        if ($RoleScope -eq 'Custom' -and $Roles.Count -eq 0) { throw 'Select at least one role when roleScope is Custom.' }

        # Role activation, eligibility, assignment, approval and notification settings.
        $Settings = ConvertTo-CIPPPIMRoleSettings -InputObject $SettingsInput
        $Floor = Test-CIPPPIMRoleSettingsFloor -Settings $Settings
        if (-not $Floor.Valid) {
            $Message = "PIM role settings template '$TemplateName' was not saved because it is below the secure floor: $($Floor.Errors -join ' ')"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error'
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = @($Message) + @($Floor.Errors | ForEach-Object { @{ resultText = $_; state = 'error' } }) }
            }
        }

        $UserDetails = try {
            ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        } catch { 'Unknown' }
        $Now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        $Table = Get-CippTable -tablename 'templates'
        $Existing = $null
        if (-not [string]::IsNullOrWhiteSpace($GUID)) {
            $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'PIMRoleSettingsTemplate' and RowKey eq '$SafeGUID'"
            if (-not $Existing) { throw "PIM role settings template $GUID was not found" }
        } else {
            $GUID = (New-Guid).Guid
        }

        $ExistingData = if ($Existing) { $Existing.JSON | ConvertFrom-Json -Depth 100 } else { $null }
        $TemplateObject = [ordered]@{
            templateName = $TemplateName
            description  = $Description
            roleScope    = $RoleScope
            roles        = @($Roles)
            settings     = $Settings
            createdBy    = $ExistingData.createdBy ?? $UserDetails
            createdDate  = $ExistingData.createdDate ?? $Now
            updatedBy    = $UserDetails
            updatedDate  = $Now
            GUID         = $GUID
        }

        $JSON = ConvertTo-Json -InputObject $TemplateObject -Depth 20 -Compress
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'PIMRoleSettingsTemplate'
            GUID         = "$GUID"
        }

        $Verb = if ($Existing) { 'Updated' } else { 'Created' }
        $Result = "$Verb PIM role settings template '$TemplateName' with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        foreach ($Adjustment in $Adjustments) {
            # Captured value was below the secure floor; the raise must be visible in the logbook.
            Write-LogMessage -headers $Headers -API $APIName -message "PIM role settings template '$TemplateName': raised to the secure floor - $Adjustment" -Sev 'Warning'
        }
        foreach ($Warning in $Floor.Warnings) {
            # Above the recommended value but inside the hard cap: allowed, and visible in the logbook.
            Write-LogMessage -headers $Headers -API $APIName -message "PIM role settings template '$TemplateName': $Warning" -Sev 'Warning'
        }
        $Results = @($Result) + @($Adjustments | ForEach-Object { @{ resultText = "Raised to the secure floor: $_"; state = 'warning' } }) + @($Floor.Warnings | ForEach-Object { @{ resultText = $_; state = 'warning' } })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = @("Failed to save PIM role settings template: $($ErrorMessage.NormalizedError)")
        Write-LogMessage -headers $Headers -API $APIName -message $Results[0] -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
