using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
if ($TenantFilter -eq 'AllTenants') {
    Push-OutputBinding -Name Msg -Value (Get-Date).ToString()
    [PSCustomObject]@{
        Tenant   = 'Report does not support all tenants'
        Licenses = 'Report does not support all tenants'
    }
}

#Build Result Table
$Result = @{
    Tenant                            = "$TenantFilter"
    ATPEnabled                        = ''
    HasAADP1                          = ''
    HasAADP2                          = ''
    HasDLP                            = ''
    DLP                               = ''
    AdminMFAV2                        = ''
    MFARegistrationV2                 = ''
    GlobalAdminCount                  = ''
    GlobalAdminList                   = ''
    BlockLegacyAuthentication         = ''
    PasswordHashSync                  = ''
    SigninRiskPolicy                  = ''
    UserRiskPolicy                    = ''
    PWAgePolicyNew                    = ''
    CustomerLockbox                   = ''
    SelfServicePasswordReset          = ''
    enableBannedPassworCheckOnPremise = ''
    accessPackages                    = ''
    SecureDefaultState                = ''
    SPSharing                         = ''
    Backupify                         = ''
    Usermfabyca                       = ''
    UserMFAbyCAname                   = ''
    PriviligedUsersCount              = ''
    PrivilegedUsersList               = ''
    AllStaleUsersList                 = ''
    AllStaleUsersCount                = ''
    SecureScorePercentage = ''
    DisabledSharedMailboxLogins = ''
    DisabledSharedMailboxLoginsCount = ''
    AdminConsentForApplications = ''
    UnifiedAuditLog = ''
    test=''
}

# Starting the CIS Framework Analyser
    
# Get the All results needed from the Secure Score
try {
    $SecureScore = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/security/secureScores?`$top=1" -tenantid $Tenantfilter -noPagination $true
    $Result.ATPEnabled = $SecureScore.enabledServices.Contains("HasEXOP2")
    $Result.HasAADP1 = $SecureScore.enabledServices.Contains("HasAADP1")
    $Result.HasAADP2 = $SecureScore.enabledServices.Contains("HasAADP2")
    $Result.HasDLP = $SecureScore.enabledServices.Contains("HasDLP")
    $Result.AdminMFAV2 = [int]($SecureScore.controlScores | where-object { $_.controlName -eq "AdminMFAv2" } | Select-Object -ExpandProperty count)
    $Result.MFARegistrationV2 = [int]($SecureScore.controlScores | where-object { $_.controlName -eq "MFARegistrationV2" } | Select-Object -ExpandProperty count)
    $Result.PasswordHashSync = $SecureScore.controlScores | where-object { $_.controlName -eq "PasswordHashSync" } | Select-Object -ExpandProperty on
    $Result.PWAgePolicyNew = [int]($SecureScore.controlScores | where-object { $_.controlName -eq "PWAgePolicyNew" } | Select-Object -ExpandProperty expiry)
    $Result.CustomerLockbox = $SecureScore.controlScores | where-object { $_.controlName -eq "CustomerLockBoxEnabled" } | Select-Object -ExpandProperty on
    $Result.SecureScorePercentage = [int](($SecureScore.currentScore / $SecureScore.maxScore) * 100)

    
    #DLP License required
    if ($result.HasDLP -eq $True) {
        $Result.DLP = $SecureScore.controlScores | where-object { $_.controlName -eq "dlp_datalossprevention" } | Select-Object -ExpandProperty on
    }
    else {
        $Result.DLP = "Not Licensed for DLP"
    }
    
    #Azure AD Premium P1 required
    if ($result.HasAADP1 -eq $True) {
        $Result.BlockLegacyAuthentication = [int]($SecureScore.controlScores | where-object { $_.controlName -eq "BlockLegacyAuthentication" } | Select-Object -ExpandProperty count)
    }
    else {
        $Result.BlockLegacyAuthentication = "Not Licensed for AADp1"
    }

    #Azure AD Premium P2 required
    if ($result.HasAADP2 -eq $True) {
        $Result.SigninRiskPolicy = [int]($SecureScore.controlScores | where-object { $_.controlName -eq "SigninRiskPolicy" } | Select-Object -ExpandProperty count)
        $Result.UserRiskPolicy = [int]($SecureScore.controlScores | where-object { $_.controlName -eq "UserRiskPolicy" } | Select-Object -ExpandProperty count)
    }
    else {
        $Result.SigninRiskPolicy = "Not Licensed for AADp2"
        $Result.UserRiskPolicy = "Not Licensed for AADp2"
    }


}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "Secure Score Retrieval on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error' 
}

#Populate Global Admin List
try {
    $GlobalAdminGraph = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/roleTemplateId=62e90394-69f5-4237-9190-012177145e10/members" -tenantid $Tenantfilter
    $Result.GlobalAdminList = ($GlobalAdminGraph | Where-object { ($_.accountEnabled -eq "True") -and ($Null -ne $_.userPrincipalName) } | Select-Object -ExpandProperty userPrincipalName) -join '<br />'
    $Result.GlobalAdminCount = ($GlobalAdminGraph | Where-object { ($_.accountEnabled -eq "True") -and ($Null -ne $_.userPrincipalName) } | Measure-Object).count
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "Global Admin List on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error' 
}

#Populate Privileged User List
try {
    $Roles = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $TenantFilter
    $AllRoleAssignments = @()
    foreach ($Role in $Roles) {
        $Members = if ($role.members) { $role.members | Where-object { ($_.accountEnabled -eq "True") -and ($Null -ne $_.userPrincipalName) } | Select-Object -ExpandProperty userPrincipalName }
        if ($Members) {
            $UserAssignment = foreach ($Member in $Members) {
                [PSCustomObject]@{
                    User        = $Member
                    DisplayName = $Role.displayName
                    Description = $Role.description
                }
            }
            $AllRoleAssignments += $UserAssignment 
        }
    }
    $Result.PrivilegedUsersList = $AllRoleAssignments
    $Result.PriviligedUsersCount = ($Result.PrivilegedUsersList.User | Measure-object).count
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "All Admin User List on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error' 
}

#Stale Licensed Users List
try {
    $StaleDate = (get-date).AddDays(-30)
    $StaleUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=accountEnabled eq true and assignedLicenses/`$count ne 0&`$count=true &`$select=displayName,userPrincipalName,signInActivity" -tenantid $TenantFilter -ComplexFilter
    $AllStaleUsers = @()
    foreach ($StaleUser in $StaleUsers) {
        $StaleUserObject = 
        [PSCustomObject]@{
            DisplayName    = $StaleUser.displayName
            UPN            = $StaleUser.userPrincipalName
            lastSignInDate = $StaleUser.signInActivity.lastSignInDateTime
        }
        if ($null -ne $StaleUserObject.lastSignInDate){
            if((get-date $StaleUserObject.lastSignInDate) -le $StaleDate){$AllStaleUsers += $StaleUserObject}
        }else{$AllStaleUsers += $StaleUserObject}
}
    $Result.AllStaleUsersList = $AllStaleUsers | sort-object lastSignInDate
    $Result.AllStaleUsersCount = ($Result.AllStaleUsersList.UPN | Measure-object).count
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "Stale User List on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error' 
}

# Get Self Service Password Reset State
try {
    $SSPRGraph = New-ClassicAPIGetRequest -Resource "74658136-14ec-4630-ad9b-26e160ff0fc6" -TenantID $TenantFilter -uri "https://main.iam.ad.ext.azure.com/api/PasswordReset/PasswordResetPolicies" -Method "GET"    
    If ($SSPRGraph.enablementType -eq 0) { $Result.SelfServicePasswordReset = 'Off' }
    If ($SSPRGraph.enablementType -eq 1) { $Result.SelfServicePasswordReset = 'Specific Users' }
    If ($SSPRGraph.enablementType -eq 2) { $Result.SelfServicePasswordReset = 'On' }
    If ([string]::IsNullOrEmpty($SSPRGraph.enablementType)) { $Result.SelfServicePasswordReset = 'Unknown' }
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "Self Service Password Reset on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error' 
}


# Check On Premise Password Protection
try {
    if ($result.HasAADP1 -eq $True) {
        $OPPPGraph = New-ClassicAPIGetRequest -Resource "74658136-14ec-4630-ad9b-26e160ff0fc6" -TenantID $TenantFilter -uri "https://main.iam.ad.ext.azure.com/api/AuthenticationMethods/PasswordPolicy" -Method "GET"
        $Result.enableBannedPassworCheckOnPremise = $OPPPGraph.enableBannedPasswordCheckOnPremises
    }
    else {
        $result.enableBannedPassworCheckOnPremise = "Not Licensed for AADp1"
    }
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "On Premise Password Protection on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error' 
}

# Check Sharepoint Sharing Settings
try {
    
    $Sharepoint = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $tenantfilter -AsApp $true
    $Result.SPSharing = $Sharepoint.sharingCapability
}
catch {
    Write-LogMessage -API 'ANSBestPracticeAnalyser' -tenant $tenant -message "Sharepoint Settings on $($tenant) Error: $($_.exception.message)" -sev 'Error'
}

# Get the Secure Default State
try {
    $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $Tenantfilter)
    $Result.SecureDefaultState = $SecureDefaultsState.IsEnabled
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "Security Defaults State on $($Tenantfilter) Error: $($_.exception.message)" -sev 'Error'
}

# Check JIT Access Packages
try {
    if ($Result.HasAADP2 -eq $True) {
        $JIT = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackages' -tenantid $Tenantfilter
        $JITCount = $JIT | measure-object -Property id | select-object -ExpandProperty count
        $Result.accessPackages = if (!$JitCount) { [int]"0" }else { $JitCount }
    }
    else {
        $Result.accessPackages = "Not Licensed for AADp2"
    }
}
catch {
    Write-LogMessage -API 'CISstandardsAnalyser' -tenant $Tenantfilter -message "JIT Access Packages on $($Tenantfilter) Error: $($_.exception.message)" -sev 'Error'
}

# Check if Backupify is Deployed
try {
    $backupifygraph = New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals?$search="displayName: Backupify"' -tenantid $tenantfilter -Complexfilter
if(!$BackupifyGraph){    $Result.Backupify = "Backupify not present"}else{$Result.Backupify = $true}
}
catch {
    Write-LogMessage -API 'ANSBestPracticeAnalyser' -tenant $tenant -message "Backupify on $($tenant) Error: $($_.exception.message)" -sev 'Error'
}

# Get Shared Mailbox Stuff
try {
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenant)/Mailbox?`$filter=RecipientTypeDetails eq 'SharedMailbox'" -Tenantid $tenant -scope ExchangeOnline)
    $AllUsersAccountState = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?select=userPrincipalName,accountEnabled' -tenantid $Tenant
    $EnabledUsersWithSharedMailbox = foreach ($SharedMailbox in $SharedMailboxList) {
        # Match the User
        $User = $AllUsersAccountState | Where-Object { $_.userPrincipalName -eq $SharedMailbox.userPrincipalName } | Select-Object -First 1
        if ($User.accountEnabled) {
            $User.userPrincipalName
        }
    }
    
    if (($EnabledUsersWithSharedMailbox | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) { $Result.DisabledSharedMailboxLogins = ($EnabledUsersWithSharedMailbox) -join '<br />' } else { $Result.DisabledSharedMailboxLogins = 'PASS' } 
    $Result.DisabledSharedMailboxLoginsCount = $EnabledUsersWithSharedMailbox | Measure-Object | Select-Object -ExpandProperty Count
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Shared Mailbox Enabled Accounts on $($tenant). Error: $($_.exception.message)" -sev 'Error'  
}


# All Users MFA CA Policy
try {
    if ($result.HasAADP1 -eq $True) {
        $CAPolicies = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $Tenantfilter
        $Result.UserMFAbyCAname = ($CAPolicies | where-object { $_.state -eq "enabled" -and $_.conditions.applications.includeApplications -eq "All" -and $_.conditions.users.includeUsers -eq "All" -and $_.grantControls.builtincontrols -eq "mfa" -and $_.conditions.userRiskLevels.length -lt 1 -and $_.conditions.signInRiskLevels.length -lt 1 } | Select-object -ExpandProperty Displayname) -join '<br />'
        $Result.UserMFAbyCA = ($Result.UserMFAbyCAname | measure-object).Count
    }
    else {
        $Result.UserMFAbyCA = "Not Licensed for AADp1"
    }
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "MFA Enforced by CA on $($Tenantfilter) Error: $($_.exception.message)" -sev 'Error'
}

# Get OAuth Admin Consenst
try {
    $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenantfilter
    $Result.AdminConsentForApplications = if ($GraphRequest.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy') { $true } else { $false }
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "OAuth Admin Consent on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error'   
}

# Get Unified Audit Log
try {
    $EXOAdminAuditLogConfig = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AdminAuditLogConfig'
    $Result.UnifiedAuditLog = $EXOAdminAuditLogConfig | Select-Object -ExpandProperty UnifiedAuditLogIngestionEnabled
    
}
catch {
    Write-LogMessage -API 'ANSSecurityAudit' -tenant $Tenantfilter -message "Unified Audit Log on $($Tenantfilter). Error: $($_.exception.message)" -sev 'Error'
}


#Display Results
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Result)
    }) -Clobber