function Connect-HuduAPI {
    [CmdletBinding()]
    param (
        $Configuration
    )

    $APIKey = Get-ExtensionAPIKey -Extension 'Hudu'

    if ($Configuration.Hudu.CFEnabled -eq $true -and $Configuration.CFZTNA.Enabled -eq $true) {
        $CFAPIKey = Get-ExtensionAPIKey -Extension 'CFZTNA'
        New-HuduCustomHeaders -Headers @{'CF-Access-Client-Id' = $Configuration.CFZTNA.ClientId; 'CF-Access-Client-Secret' = "$CFAPIKey" }
        Write-Information 'CF-Access-Client-Id and CF-Access-Client-Secret headers added to Hudu API request'
    }
    New-HuduBaseURL -BaseURL $Configuration.Hudu.BaseURL
    New-HuduAPIKey -ApiKey $APIKey
}
