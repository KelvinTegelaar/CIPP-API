function Invoke-CIPPStandardAPESP {
  <#
    .FUNCTIONALITY
    Internal
    #>
  param($Tenant, $Settings)
  If ($Settings.remediate) {
    $APINAME = 'Standards'
    try {
      Set-CIPPDefaultAPEnrollment -TenantFilter $Tenant -ShowProgress $Settings.ShowProgress -BlockDevice $Settings.blockDevice -AllowReset $Settings.AllowReset -EnableLog $Settings.EnableLog -ErrorMessage $Settings.ErrorMessage -TimeOutInMinutes $Settings.TimeOutInMinutes -AllowFail $Settings.AllowFail -OBEEOnly $Settings.OBEEOnly
    } catch {
      Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create default Autopilot Enrollment: $($_.exception.message)" -sev 'Error'
    }
  }


}