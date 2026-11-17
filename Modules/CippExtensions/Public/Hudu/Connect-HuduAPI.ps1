function Connect-HuduAPI {
    [CmdletBinding()]
    param ()

    # Read the stored config so the API key only ever goes to the saved Hudu URL.
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json

    $APIKey = Get-ExtensionAPIKey -Extension 'Hudu'

    if ($Configuration.Hudu.CFEnabled -eq $true -and $Configuration.CFZTNA.Enabled -eq $true) {
        $CFAPIKey = Get-ExtensionAPIKey -Extension 'CFZTNA'
        New-HuduCustomHeaders -Headers @{'CF-Access-Client-Id' = $Configuration.CFZTNA.ClientId; 'CF-Access-Client-Secret' = "$CFAPIKey" }
        Write-Information 'CF-Access-Client-Id and CF-Access-Client-Secret headers added to Hudu API request'
    }
    $null = Set-HuduRequestOption -SkipPostRetry $true -RateLimitWindowSeconds 30
    New-HuduBaseURL -BaseURL $Configuration.Hudu.BaseURL
    New-HuduAPIKey -ApiKey $APIKey
}
