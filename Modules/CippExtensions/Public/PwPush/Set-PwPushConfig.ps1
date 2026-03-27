function Set-PwPushConfig {
    <#
    .SYNOPSIS
    Sets PwPush configuration

    .DESCRIPTION
    Sets PwPush configuration from CIPP Extension config

    .PARAMETER Configuration
    Configuration object

    .PARAMETER FullConfiguration
    Full parsed configuration object including CFZTNA settings
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $Configuration,
        $FullConfiguration
    )
    $InitParams = @{}
    if ($Configuration.BaseUrl) {
        $InitParams.BaseUrl = $Configuration.BaseUrl
    }
    if (![string]::IsNullOrEmpty($Configuration.EmailAddress) -or $Configuration.UseBearerAuth -eq $true) {
        $ApiKey = Get-ExtensionAPIKey -Extension 'PWPush'
        if ($Configuration.UseBearerAuth -eq $true) {
            $InitParams.Bearer = $ApiKey
        } elseif (![string]::IsNullOrEmpty($ApiKey)) {
            if (![string]::IsNullOrEmpty($Configuration.EmailAddress)) {
                $InitParams.EmailAddress = $Configuration.EmailAddress
            }
            $InitParams.APIKey = $ApiKey
        }
    }

    $Module = Get-Module PassPushPosh -ListAvailable
    Write-Information "PWPush Version: $($Module.Version)"
    if ($PSCmdlet.ShouldProcess('Initialize-PassPushPosh')) {
        Write-Information ($InitParams | ConvertTo-Json)
        Initialize-PassPushPosh @InitParams
    }

    if ($Configuration.CFEnabled -eq $true -and $FullConfiguration.CFZTNA.Enabled -eq $true) {
        $CFAPIKey = Get-ExtensionAPIKey -Extension 'CFZTNA'
        $PPPModule = Get-Module PassPushPosh
        & $PPPModule {
            if (-not $Script:PPPHeaders) {
                $Script:PPPHeaders = @{}
            }
            $Script:PPPHeaders['CF-Access-Client-Id'] = $args[0]
            $Script:PPPHeaders['CF-Access-Client-Secret'] = $args[1]
        } $FullConfiguration.CFZTNA.ClientId "$CFAPIKey"
        Write-Information 'CF-Access-Client-Id and CF-Access-Client-Secret headers added to PWPush API request'
    }
}

