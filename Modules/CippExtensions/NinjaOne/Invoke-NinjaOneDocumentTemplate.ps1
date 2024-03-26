function Invoke-NinjaOneDocumentTemplate {
    [CmdletBinding()]
    param (
        $Template,
        $Token,
        $ID
    )

    if (!$Token) {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne
        $Token = Get-NinjaOneToken -configuration $Configuration
    }

    if (!$ID) {
        $DocumentTemplates = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/document-templates/" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
        $DocumentTemplate = $DocumentTemplates | Where-Object { $_.name -eq $Template.name }
    } else {
        $DocumentTemplate = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/document-templates/$($ID)" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -Depth 100
    }
    
    $MatchedCount = ($DocumentTemplate | Measure-Object).count
    if ($MatchedCount -eq 1) {
        # Matched a single document template
        $NinjaDocumentTemplate = $DocumentTemplate
    } elseif ($MatchedCount -eq 0) {
        # Create a new Document Template
        $Body = $Template | ConvertTo-Json -Depth 100
        Write-Host "Ninja Body: $body"
        $NinjaDocumentTemplate = (Invoke-WebRequest -Uri "https://$($Configuration.Instance)/api/v2/document-templates/" -Method POST -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json' -Body $Body).content | ConvertFrom-Json -Depth 100
    } else {
        # Matched multiple templates. Should be impossible but lets check anyway :D
        Throw 'Multiple Documents Matched the Provided Criteria'
    }

    return $NinjaDocumentTemplate

}