function Invoke-CippTestSMB1001_4_7 {
    <#
    .SYNOPSIS
    Tests SMB1001 (4.7) - Ensure all computer devices that store sensitive information are
    disposed of securely

    .DESCRIPTION
    SMB1001 4.7 requires permanent destruction or non-recoverable formatting of storage media
    on decommissioned devices. The physical-disposal step happens outside Microsoft 365.
    This test is informational so the disposal procedure is evidenced separately.
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'SMB1001_4_7' -TestType 'Devices' -Status 'Informational' -ResultMarkdown 'This is a task performed manually. SMB1001 (4.7) requires devices that store sensitive, private, or confidential information to be disposed of securely — by physical destruction (shredder or external service) or non-recoverable formatting if the device is reused or sold. Evidence the disposal procedure (destruction certificates, asset disposal log) to your Dynamic Standard Certifier separately. Configuring an Intune managed-device cleanup rule helps remove corporate data from inactive devices but does not satisfy the physical-disposal requirement on its own.' -Risk 'Informational' -Name 'Devices that store sensitive information are disposed of securely' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
}
