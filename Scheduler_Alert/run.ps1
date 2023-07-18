param($tenant)

try {

    $Table = Get-CIPPTable -Table SchedulerConfig
    if ($Tenant.tag -eq 'AllTenants') {
        $Filter = "RowKey eq 'AllTenants' and PartitionKey eq 'Alert'"
    }
    else {
        $Filter = "RowKey eq '{0}' and PartitionKey eq 'Alert'" -f $Tenant.tenantid
    }
    $Alerts = Get-AzDataTableEntity @Table -Filter $Filter

    $DeltaTable = Get-CIPPTable -Table DeltaCompare
    $LastRunTable = Get-CIPPTable -Table AlertLastRun

    $ShippedAlerts = switch ($Alerts) {
        { $_.'AdminPassword' -eq $true } {
            try {
                New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'&`$expand=principal" -tenantid $($tenant.tenant) | Where-Object {($_.principalOrganizationId -EQ $tenant.tenantid) -and ($_.principal.'@odata.type' -eq '#microsoft.graph.user')} | ForEach-Object {
                    $LastChanges = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.principalId)?`$select=UserPrincipalName,lastPasswordChangeDateTime" -tenant $($tenant.tenant)
                    if ($LastChanges.LastPasswordChangeDateTime -gt (Get-Date).AddDays(-1)) { "Admin password has been changed for $($LastChanges.UserPrincipalName) in last 24 hours" }
                }

            }
            catch {
                "Could not get admin password changes for $($Tenant.tenant): $($_.Exception.message)"
            }
        }
        { $_.'DefenderMalware' -eq $true } {
            try {
                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsDeviceMalwareStates?`$top=999&`$filter=tenantId eq '$($Tenant.tenantid)'" | Where-Object { $_.malwareThreatState -eq 'Active' } | ForEach-Object {
                    "$($_.managedDeviceName): Malware found and active. Severity: $($_.MalwareSeverity). Malware name: $($_.MalwareDisplayName)"
                }
            }
            catch {

            }
        }

        { $_.'DefenderStatus' -eq $true } {
            try {
                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsProtectionStates?`$top=999&`$filter=tenantId eq '$($Tenant.tenantid)'" | Where-Object { $_.realTimeProtectionEnabled -eq $false -or $_.MalwareprotectionEnabled -eq $false } | ForEach-Object {
                    "$($_.managedDeviceName) - Real Time Protection: $($_.realTimeProtectionEnabled) & Malware Protection: $($_.MalwareprotectionEnabled)"
                }
            }
            catch {

            }
        }
        { $_.'MFAAdmins' -eq $true } {
            try {
                $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
                $AdminList = (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$expand=members" -tenantid $($tenant.tenant) | Where-Object -Property roleTemplateId -NE 'd29b2b05-8046-44ba-8758-1e26182fcf32').members | Where-Object { $_.userPrincipalName -ne $null -and $_.Usertype -eq 'Member' -and $_.accountEnabled -eq $true } | Sort-Object UserPrincipalName -Unique
                $AdminList | ForEach-Object {
                    $CARegistered = $null
                    try {
            (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.ID)/authentication/Methods" -tenantid $($tenant.tenant)) | ForEach-Object {
                            if ($_.'@odata.type' -in $StrongMFAMethods) {
                                $CARegistered = $true;
                            }
                        }
                        if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -eq $null -and $CARegistered -ne $true) { "Admin $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." }
                    }
                    catch {
                    }
                }
            }
            catch {
                "Could not get MFA status for admins for $($Tenant.tenant): $($_.Exception.message)"
            }
        }
        { $_.'MFAAlertUsers' -eq $true } {
            try {
                $users = Get-CIPPMSolUsers -tenant $tenant.tenant
                $StrongMFAMethods = '#microsoft.graph.fido2AuthenticationMethod', '#microsoft.graph.phoneAuthenticationMethod', '#microsoft.graph.passwordlessmicrosoftauthenticatorauthenticationmethod', '#microsoft.graph.softwareOathAuthenticationMethod', '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'

                $users | Where-Object { $_.Usertype -eq 'Member' -and $_.BlockCredential -eq $false } | ForEach-Object {
                    try {
                (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.ObjectID)/authentication/Methods" -tenantid $($tenant.tenant)) | ForEach-Object {
                            if ($_.'@odata.type' -in $StrongMFAMethods -and !$CARegistered) {
                                $CARegistered = $true;
                            } }
                        if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -eq $null -and $CARegistered -eq $false) { "User $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." }
                    }
                    catch {
                        $CARegistered = $false
                    }
                }

            }
            catch {
                "Could not get MFA status for users for $($Tenant.tenant): $($_.Exception.message)"

            }
        }

        { $_.'NewRole' -eq $true } {
            try {
                $Filter = "PartitionKey eq 'AdminDelta' and RowKey eq '{0}'" -f $Tenant.tenantid
                $AdminDelta = (Get-AzDataTableEntity @Deltatable -Filter $Filter).delta | ConvertFrom-Json -ErrorAction SilentlyContinue
                $NewDelta = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $Tenant.tenant) | Select-Object displayname, Members | ForEach-Object {
                    @{
                        GroupName = $_.displayname
                        Members   = $_.Members.UserPrincipalName
                    }
                }
                $NewDeltatoSave = $NewDelta | ConvertTo-Json -Depth 10 -Compress -ErrorAction SilentlyContinue | Out-String
                $DeltaEntity = @{
                    PartitionKey = 'AdminDelta'
                    RowKey       = [string]$Tenant.tenantid
                    delta        = "$NewDeltatoSave"
                }
                Add-AzDataTableEntity @DeltaTable -Entity $DeltaEntity -Force

                if ($AdminDelta) {
                    foreach ($Group in $NewDelta) {
                        $OldDelta = $AdminDelta | Where-Object { $_.GroupName -eq $Group.GroupName }
                        $Group.members | Where-Object { $_ -notin $OldDelta.members } | ForEach-Object {
                            "$_ has been added to the $($Group.GroupName) Role"
                        }
                    }
                }
            }
            catch {
                "Could not get get role changes for $($Tenant.tenant): $($_.Exception.message)"

            }
        }
        { $_.'QuotaUsed' -eq $true } {
            try {
                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $Tenant.tenant | ForEach-Object {
                    $PercentLeft = [math]::round($_.StorageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes * 100)
                    if ($PercentLeft -gt 90) { "$($_.UserPrincipalName): Mailbox has less than 10% space left. Mailbox is $PercentLeft% full" }
                }
            }
            catch {

            }
        }
        { $_.'NoCAConfig' -eq $true } {
            try {
                $CAAvailable = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $Tenant.Tenant -erroraction stop).serviceplans
                if ('AAD_PREMIUM' -in $CAAvailable.servicePlanName) {
                    $CAPolicies = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $Tenant.Tenant)
                    if (!$CAPolicies.id) {
                        'Conditional Access is available, but no policies could be found.'
                    }
                }
            }
            catch {
            }
        }
        { $_.'UnusedLicenses' -eq $true } {
            try {
                #$ConvertTable = Import-Csv Conversiontable.csv
                $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
                $ExcludedSkuList = Get-AzDataTableEntity @LicenseTable
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $Tenant.tenant | ForEach-Object {
                    $skuid = $_
                    foreach ($sku in $skuid) {
                        if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
                        $PrettyName = ($ConvertTable | Where-Object { $_.GUID -eq $_.skuid }).'Product_Display_Name' | Select-Object -Last 1
                        if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                        if ($sku.prepaidUnits.enabled - $sku.consumedUnits -gt 0) {
                            "$PrettyName has unused licenses. Using $($_.consumedUnits) of $($_.prepaidUnits.enabled)."
                        }
                    }
                }
            }
            catch {

            }
        }
        { $_.'OverusedLicenses' -eq $true } {
            try {
                #$ConvertTable = Import-Csv Conversiontable.csv
                $LicenseTable = Get-CIPPTable -TableName ExcludedLicenses
                $ExcludedSkuList = Get-AzDataTableEntity @LicenseTable
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $Tenant.tenant | ForEach-Object {
                    $skuid = $_
                    foreach ($sku in $skuid) {
                        if ($sku.skuId -in $ExcludedSkuList.GUID) { continue }
                        $PrettyName = ($ConvertTable | Where-Object { $_.GUID -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
                        if (!$PrettyName) { $PrettyName = $sku.skuPartNumber }
                        if ($sku.prepaidUnits.enabled - $sku.consumedUnits -lt 0) {
                            "$PrettyName has Overused licenses. Using $($_.consumedUnits) of $($_.prepaidUnits.enabled)."
                        }
                    }
                }
            }
            catch {

            }
        }
        { $_.'AppSecretExpiry' -eq $true } {
            try {
                $Filter = "RowKey eq 'AppSecretExpiry' and PartitionKey eq '{0}'" -f $Tenant.tenantid
                $LastRun = Get-AzDataTableEntity @LastRunTable -Filter $Filter
                $Yesterday = (Get-Date).AddDays(-1)
                if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
                    New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,passwordCredentials" -tenantid $Tenant.tenant | ForEach-Object {
                        foreach ($App in $_) {
                            if ($App.passwordCredentials) {
                                foreach ($Credential in $App.passwordCredentials) {
                                    if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                                        "Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime
                                    }
                                }
                            }
                        }
                    }
                    $LastRun = @{
                        RowKey       = 'AppSecretExpiry'
                        PartitionKey = $Tenant.tenantid
                    }
                    Add-AzDataTableEntity @LastRunTable -Entity $LastRun -Force
                }
            }
            catch {
                #$Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
                #Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
            }
        }
        { $_.'ApnCertExpiry' -eq $true } {
            try {
                $Filter = "RowKey eq 'ApnCertExpiry' and PartitionKey eq '{0}'" -f $Tenant.tenantid
                $LastRun = Get-AzDataTableEntity @LastRunTable -Filter $Filter
                $Yesterday = (Get-Date).AddDays(-1)
                if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
                    try {
                        $Apn = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/applePushNotificationCertificate' -tenantid $Tenant.tenant
                        if ($Apn.expirationDateTime -lt (Get-Date).AddDays(30) -and $Apn.expirationDateTime -gt (Get-Date).AddDays(-7)) {
                            'Intune: Apple Push Notification certificate for {0} is expiring on {1}' -f $Apn.appleIdentifier, $Apn.expirationDateTime
                        }
                    }
                    catch {}
                }
                $LastRun = @{
                    RowKey       = 'ApnCertExpiry'
                    PartitionKey = $Tenant.tenantid
                }
                Add-AzDataTableEntity @LastRunTable -Entity $LastRun -Force
            }
            catch {
                #$Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
                #Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
            }
        }
        { $_.'VppTokenExpiry' -eq $true } {
            try {
                $Filter = "RowKey eq 'VppTokenExpiry' and PartitionKey eq '{0}'" -f $Tenant.tenantid
                $LastRun = Get-AzDataTableEntity @LastRunTable -Filter $Filter
                $Yesterday = (Get-Date).AddDays(-1)
                if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
                    try {
                        $VppTokens = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/vppTokens' -tenantid $Tenant.tenant).value
                        foreach ($Vpp in $VppTokens) {
                            if ($Vpp.state -ne 'valid') {
                                'Apple Volume Purchase Program Token is not valid, new token required'
                            }
                            if ($Vpp.expirationDateTime -lt (Get-Date).AddDays(30) -and $Vpp.expirationDateTime -gt (Get-Date).AddDays(-7)) {
                                'Apple Volume Purchase Program token expiring on {0}' -f $Vpp.expirationDateTime
                            }
                        }
                    }
                    catch {}
                    $LastRun = @{
                        RowKey       = 'VppTokenExpiry'
                        PartitionKey = $Tenant.tenantid
                    }
                    Add-AzDataTableEntity @LastRunTable -Entity $LastRun -Force
                }
            }
            catch {
                #$Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
                #Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
            }
        }
        { $_.'DepTokenExpiry' -eq $true } {
            try {
                $Filter = "RowKey eq 'DepTokenExpiry' and PartitionKey eq '{0}'" -f $Tenant.tenantid
                $LastRun = Get-AzDataTableEntity @LastRunTable -Filter $Filter
                $Yesterday = (Get-Date).AddDays(-1)
                if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
                    try {
                        $DepTokens = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $Tenant.tenant).value
                        foreach ($Dep in $DepTokens) {
                            if ($Dep.tokenExpirationDateTime -lt (Get-Date).AddDays(30) -and $Dep.tokenExpirationDateTime -gt (Get-Date).AddDays(-7)) {
                                'Apple Device Enrollment Program token expiring on {0}' -f $Dep.tokenExpirationDateTime
                            }
                        }
                    }
                    catch {}
                    $LastRun = @{
                        RowKey       = 'DepTokenExpiry'
                        PartitionKey = $Tenant.tenantid
                    }
                    Add-AzDataTableEntity @LastRunTable -Entity $LastRun -Force
                }
            }
            catch {
                #$Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
                #Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
            }
        }
        { $_.'SecDefaultsUpsell' -eq $true } {
            try {
                $Filter = "RowKey eq 'SecDefaultsUpsell' and PartitionKey eq '{0}'" -f $Tenant.tenantid
                $LastRun = Get-AzDataTableEntity @LastRunTable -Filter $Filter
                $Yesterday = (Get-Date).AddDays(-1)
                if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
                    try {
                        $SecDefaults = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $Tenant.tenant)
                        if ($SecDefaults.isEnabled -eq $false -and $SecDefaults.securityDefaultsUpsell.action -in @('autoEnable', 'autoEnabledNotify')) {
                            'Security Defaults will be automatically enabled on {0}' -f $SecDefaults.securityDefaultsUpsell.dueDateTime
                        }
                    }
                    catch {}
                    $LastRun = @{
                        RowKey       = 'SecDefaultsUpsell'
                        PartitionKey = $Tenant.tenantid
                    }
                    Add-AzDataTableEntity @LastRunTable -Entity $LastRun -Force
                }
            }
            catch {
                #$Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
                #Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
            }
        }
    }

    $Table = Get-CIPPTable
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $tenant.tenant
    Write-Host $Filter
    $currentlog = Get-AzDataTableEntity @Table -Filter $Filter

    $ShippedAlerts | ForEach-Object {
        if ($_ -notin $currentlog.Message) {
            Write-LogMessage -message $_ -API 'Alerts' -tenant $tenant.tenant -sev Alert
        }
    }
    [PSCustomObject]@{
        ReturnedValues = $true
    }
}
catch {
    $Message = 'Exception on line {0} - {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
    Write-LogMessage -message $Message -API 'Alerts' -tenant $tenant.tenant -sev Error
    [PSCustomObject]@{
        ReturnedValues = $false
    }
}
