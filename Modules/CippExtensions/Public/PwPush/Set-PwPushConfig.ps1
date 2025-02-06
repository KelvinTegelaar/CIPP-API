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
    if (![string]::IsNullOrEmpty($Configuration.EmailAddress) -or $Configuration.PWPushPro -eq $true) {
        $ApiKey = Get-ExtensionAPIKey -Extension 'PWPush'

        if (![string]::IsNullOrEmpty($ApiKey)) {
            $InitParams.APIKey = $ApiKey
        }
        if (![string]::IsNullOrEmpty($Configuration.EmailAddress)) {
            $InitParams.EmailAddress = $Configuration.EmailAddress
        }
        if ($Configuration.PWPushPro -eq $true) {
            $InitParams.AccountType = 'Pro'
            $InitParams.Remove('BaseUrl')
        }
    }
    Write-Information ($InitParams | ConvertTo-Json)

    $Module = Get-Module PassPushPosh -ListAvailable
    Write-Host $Module.Version
    if ($PSCmdlet.ShouldProcess('Initialize-PassPushPosh')) {
        Initialize-PassPushPosh @InitParams
    }
}

