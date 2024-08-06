function Set-CIPPDefaultAPEnrollment {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $ShowProgress,
        $BlockDevice,
        $AllowReset,
        $EnableLog,
        $ErrorMessage,
        $TimeOutInMinutes,
        $AllowFail,
        $OBEEOnly,
        $ExecutingUser,
        $APIName = 'Add Default Enrollment Status Page'
    )

    $User = $request.headers.'x-ms-client-principal-name'

    try {
        $ObjBody = [pscustomobject]@{
            '@odata.type'                             = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'
            'id'                                      = 'DefaultWindows10EnrollmentCompletionPageConfiguration'
            'displayName'                             = 'All users and all devices'
            'description'                             = 'This is the default enrollment status screen configuration applied with the lowest priority to all users and all devices regardless of group membership.'
            'showInstallationProgress'                = [bool]$ShowProgress
            'blockDeviceSetupRetryByUser'             = ![bool]$blockDevice
            'allowDeviceResetOnInstallFailure'        = [bool]$AllowReset
            'allowLogCollectionOnInstallFailure'      = [bool]$EnableLog
            'customErrorMessage'                      = "$ErrorMessage"
            'installProgressTimeoutInMinutes'         = $TimeOutInMinutes
            'allowDeviceUseOnInstallFailure'          = [bool]$AllowFail
            'selectedMobileAppIds'                    = @()
            'trackInstallProgressForAutopilotOnly'    = [bool]$OBEEOnly
            'disableUserStatusTrackingAfterFirstUser' = $true
            'roleScopeTagIds'                         = @()
        }
        $Body = ConvertTo-Json -InputObject $ObjBody
        $ExistingStatusPage = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations' -tenantid $($TenantFilter)) | Where-Object { $_.id -like '*DefaultWindows10EnrollmentCompletionPageConfiguration' }

        if ($PSCmdlet.ShouldProcess($ExistingStatusPage.ID, 'Set Default Enrollment Status Page')) {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($ExistingStatusPage.ID)" -body $body -Type PATCH -tenantid $($TenantFilter)
            "Successfully changed default enrollment status page for $($($TenantFilter))"
            Write-LogMessage -user $User -API $APINAME -tenant $($TenantFilter) -message "Added Autopilot Enrollment Status Page $($Displayname)" -Sev 'Info'
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -tenant $($TenantFilter) -message "Failed adding Autopilot Enrollment Status Page $($Displayname). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to change default enrollment status page for $($($TenantFilter)): $($ErrorMessage.NormalizedError)"
    }
}
