using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$Tenants = Get-ChildItem "Cache_Standards\*.standards.json"

$CurrentStandards = foreach ($tenant in $tenants) {
    $StandardsFile = Get-Content "$($tenant)" | ConvertFrom-Json
    if ($null -eq $StandardsFile.Tenant) { continue }
    [PSCustomObject]@{
        displayName                  = $StandardsFile.tenant
        appliedBy                    = $StandardsFile.addedby
        appliedAt                    = ($tenant).LastWriteTime.toString('s')
        "DisableBasicAuth"           = $StandardsFile.standards.DisableBasicAuth
        "ModernAuth"                 = $StandardsFile.standards.ModernAuth
        "AuditLog"                   = $StandardsFile.standards.AuditLog
        "AutoExpandArchive"          = $StandardsFile.standards.AutoExpandArchive
        "SecurityDefaults"           = $StandardsFile.standards.SecurityDefaults
        "DisableSharedMailbox"       = $StandardsFile.standards.DisableSharedMailbox
        "UndoOauth"                  = $StandardsFile.standards.UndoOauth
        "DisableSelfServiceLicenses" = $StandardsFile.standards.DisableSelfServiceLicenses
        "AnonReportDisable"          = $StandardsFile.standards.AnonReportDisable
        "UndoSSPR"                   = $StandardsFile.standards.UndoSSPR
        "PasswordExpireDisabled"     = $StandardsFile.standards.PasswordExpireDisabled
        "DelegateSentItems"          = $StandardsFile.standards.DelegateSentItems
        "OauthConsent"               = $StandardsFile.standards.OauthConsent
        "SSPR"                       = $StandardsFile.standards.SSPR
        "LegacyMFA"                  = $StandardsFile.standards.LegacyMFA
        "SpoofWarn"                  = $StandardsFile.standards.SpoofWarn
    }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentStandards)
    })
