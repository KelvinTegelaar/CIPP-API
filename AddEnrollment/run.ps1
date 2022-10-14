using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Input bindings are passed in via param block.
$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Profbod = $Request.body
$results = foreach ($Tenant in $tenants) {
    try {
        $ObjBody = [pscustomobject]@{
            "@odata.type"                             = "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
            "id"                                      = "DefaultWindows10EnrollmentCompletionPageConfiguration"
            "displayName"                             = "All users and all devices"
            "description"                             = "This is the default enrollment status screen configuration applied with the lowest priority to all users and all devices regardless of group membership."
            "showInstallationProgress"                = [bool]$Profbod.ShowProgress
            "blockDeviceSetupRetryByUser"             = [bool]$Profbod.blockDevice
            "allowDeviceResetOnInstallFailure"        = [bool]$Profbod.AllowReset
            "allowLogCollectionOnInstallFailure"      = [bool]$Profbod.EnableLog
            "customErrorMessage"                      = $Profbod.ErrorMessage
            "installProgressTimeoutInMinutes"         = $Profbod.TimeOutInMinutes
            "allowDeviceUseOnInstallFailure"          = [bool]$Profbod.AllowFail
            "selectedMobileAppIds"                    = @()
            "trackInstallProgressForAutopilotOnly"    = [bool]$Profbod.OBEEOnly
            "disableUserStatusTrackingAfterFirstUser" = $true
            "roleScopeTagIds"                         = @()
        }
        $Body = ConvertTo-Json -InputObject $ObjBody
        Write-Host $body
        $ExistingStatusPage = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations" -tenantid $Tenant) | Where-Object { $_.id -like "*DefaultWindows10EnrollmentCompletionPageConfiguration" }
        $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($ExistingStatusPage.ID)" -body $body -Type PATCH -tenantid $tenant
        "Successfully changed default enrollment status page for $($Tenant)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Added Autopilot Enrollment Status Page $($Displayname)" -Sev "Info"

    }
    catch {
        "Failed to change default enrollment status page for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Failed adding Autopilot Enrollment Status Page $($Displayname). Error: $($_.Exception.Message)" -Sev "Error"
        continue
    }

}

$body = [pscustomobject]@{"Results" = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
