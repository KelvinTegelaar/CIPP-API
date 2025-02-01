function Set-PwPushConfig {
    <#
    .SYNOPSIS
    Sets PwPush configuration

    .DESCRIPTION
    Sets PwPush configuration from CIPP Extension config

    .PARAMETER Configuration
    Configuration object
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $Configuration
    )
    $InitParams = @{}
    if ($Configuration.BaseUrl) {
        $InitParams.BaseUrl = $Configuration.BaseUrl
    }
    if (![string]::IsNullOrEmpty($Configuration.EmailAddress)) {
        $ApiKey = Get-ExtensionAPIKey -Extension 'PWPush'

        if (![string]::IsNullOrEmpty($ApiKey)) {
            $InitParams.APIKey = $ApiKey
            $InitParams.EmailAddress = $Configuration.EmailAddress
        }
    }
    if ($PSCmdlet.ShouldProcess('Initialize-PassPushPosh')) {
        Initialize-PassPushPosh @InitParams
    }
}
