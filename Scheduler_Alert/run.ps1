param($tenant)
Write-Host $($Tenant | ConvertTo-Json)
if ($Tenant.tag -eq "AllTenants") {
    $Alerts = Get-Content ".\Cache_Scheduler\AllTenants.alert.json" | ConvertFrom-Json
}
else {
    $Alerts = Get-Content ".\Cache_Scheduler\$($tenant.tenant).alert.json" | ConvertFrom-Json
}
$ShippedAlerts = switch ($Alerts) {
   
    { $Alerts."AdminPassword" -eq $true } {
        New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'" -tenantid $($tenant.tenant) | ForEach-Object { 
            $LastChanges = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.principalId)?`$select=UserPrincipalName,lastPasswordChangeDateTime" -tenant $($tenant.tenant)
            if ([datetime]$LastChanges.LastPasswordChangeDateTime -gt (Get-Date).AddDays(-1)) { "Admin password has been changed for $($LastChanges.UserPrincipalName) in last 24 hours" }
        }
    }
    { $_."DefenderMalware" -eq $true } {

        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsDeviceMalwareStates?`$top=999&`$filter=tenantId eq '$($Tenant.tenantid)'" | Where-Object { $_.malwareThreatState -eq "Active" } | ForEach-Object {
            "$($_.managedDeviceName): Malware found and active. Severity: $($_.MalwareSeverity). Malware name: $($_.MalwareDisplayName)"
        }
    }
    { $_."DefenderStatus" -eq $true } {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsProtectionStates?`$top=999&`$filter=tenantId eq '$($Tenant.tenantid)'" | Where-Object { $_.realTimeProtectionEnabled -eq $false -or $_.MalwareprotectionEnabled -eq $false } | ForEach-Object {
            "$($_.managedDeviceName) - Real Time Protection: $($_.realTimeProtectionEnabled) & Malware Protection: $($_.MalwareprotectionEnabled)"
        }
    }
    { $_."MFAAdmins" -eq $true } {
        $AdminIds = (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'&expand=principal" -tenantid $($tenant.tenant)).principal
        $AdminList = Get-CIPPMSolUsers -tenant $tenant.tenant | Where-Object -Property ObjectID -In $AdminIds.id
        try { $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $tenant.tenant -ErrorAction) } catch {}
        $AdminList | Where-Object { $_.Usertype -eq "Member" -and $_.BlockCredential -eq $false } | ForEach-Object {
            $CARegistered = [boolean]($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered
            if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -eq $null -and $CARegistered -eq $false) { "Admin $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." }
        }
    }
    { $_."MFAAlertUsers" -eq $true } {
        $users = Get-CIPPMSolUsers -tenant $tenant.tenant
        try { $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $tenant.tenant -ErrorAction) } catch {}
        $users | Where-Object { $_.Usertype -eq "Member" -and $_.BlockCredential -eq $false } | ForEach-Object {
            $CARegistered = [boolean]($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered
            if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -eq $null -and $CARegistered -eq $false) { "User $($_.UserPrincipalName) is enabled but does not have any form of MFA configured." }
        }
    }

    { $_."NewRole" -eq $true } {
        $AdminDelta = Get-Content ".\Cache_AlertsCheck\$($Tenant.tenant).AdminDelta.json" | ConvertFrom-Json
        $NewDelta = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles?`$expand=members" -tenantid $Tenant.tenant) | Select-Object displayname, Members | ForEach-Object {
            [PSCustomObject]@{
                GroupName = $_.displayname
                Members   = $_.Members.UserPrincipalName
            }
        }
        $null = New-Item ".\Cache_AlertsCheck\$($Tenant.tenant).AdminDelta.json" -Value ($NewDelta | ConvertTo-Json) -Force
        if ($AdminDelta) {
            foreach ($Group in $NewDelta) {
                $OldDelta = $AdminDelta | Where-Object { $_.GroupName -eq $Group.GroupName }
                $Group.members | Where-Object { $_ -notin $OldDelta.members } | ForEach-Object {
                    "$_ has been added to the $($Group.GroupName) Role"
                }
            }
        }
    }
    { $_."QuotaUsed" -eq $true } {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $Tenant.tenant | ForEach-Object {
            $PercentLeft = [math]::round($_.StorageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes * 100)
            if ($PercentLeft -gt 80) { "$($_.UserPrincipalName): Mailbox has less than 10% space left. Mailbox is $PercentLeft% full" }
        }
    }
    { $Alerts."UnusedLicenses" -eq $true } {
        $ConvertTable = Import-Csv Conversiontable.csv
        $ExcludedSkuList = Get-Content ".\config\ExcludeSkuList.json" | ConvertFrom-Json
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/subscribedSkus" -tenantid $Tenant.tenant | ForEach-Object {
            $skuid = $_
            foreach ($sku in $skuid) {
                if ($sku.skuId -in $ExcludedSkuList.guid) { continue }
                $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $sku.skuid }).'Product_Display_Name' | Select-Object -Last 1
                if (!$PrettyName) { $PrettyName = $skuid.skuPartNumber }

                if ($sku.prepaidUnits.enabled - $sku.consumedUnits -ne 0) {
                    "$PrettyName has unused licenses. Using $($sku.consumedUnits) of $($sku.prepaidUnits.enabled)."
                }
            }
        }
    }
}
$currentlog = Get-Content "Logs\$((Get-Date).ToString('ddMMyyyy')).log" | ForEach-Object {
    try {
        $_ | ConvertFrom-Csv -Header "DateTime", "Tenant", "API", "Message", "User", "Severity" -Delimiter "|" | Where-Object -Property Tenant -EQ $tenant.tenant
    }
    catch {

    }
}
Write-Host $ShippedAlerts
$ShippedAlerts | ForEach-Object {
    if ($_ -in $currentlog.message) {
        continue
    }
    Log-Request -message $_ -API "Alerts" -tenant $tenant.tenant -sev Alert
}
[PSCustomObject]@{
    ReturnedValues = $true
}