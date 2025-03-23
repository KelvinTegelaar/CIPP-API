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
}

