function Invoke-EditJITRoleTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .DESCRIPTION
        Updates an existing JIT Role Template.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $GUID = $Request.Body.GUID
        $TemplateName = $Request.Body.templateName

        if ([string]::IsNullOrWhiteSpace($GUID)) {
            throw 'GUID is required'
        }
        if ([string]::IsNullOrWhiteSpace($TemplateName)) {
            throw 'templateName is required'
        }
        if (-not $Request.Body.roles -or @($Request.Body.roles).Count -eq 0) {
            throw 'At least one role is required'
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Editing JIT Role template '$GUID'" -Sev 'Info'

        $UserDetails = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

        $Table = Get-CippTable -tablename 'templates'
        $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type Guid
        $Filter = "PartitionKey eq 'JITRoleTemplate' and RowKey eq '$SafeGUID'"
        $ExistingTemplate = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (!$ExistingTemplate) {
            throw "JIT Role Template with GUID '$GUID' not found"
        }

        $ExistingData = $ExistingTemplate.JSON | ConvertFrom-Json -Depth 100

        # Check if template name is unique (excluding current template)
        $AllTemplates = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'JITRoleTemplate'"
        $DuplicateName = $AllTemplates | Where-Object { $_.RowKey -ne $GUID } | ForEach-Object {
            try {
                $data = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                if ($data.templateName -eq $TemplateName) {
                    $data
                }
            } catch {}
        }

        if ($DuplicateName) {
            throw "A JIT Role Template with name '$TemplateName' already exists"
        }

        $TemplateObject = @{
            templateName = $TemplateName
            roles        = $Request.Body.roles
            createdBy    = $ExistingData.createdBy
            createdDate  = $ExistingData.createdDate
            modifiedBy   = $UserDetails
            modifiedDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        $JSON = ConvertTo-Json -InputObject $TemplateObject -Depth 100 -Compress

        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'JITRoleTemplate'
            GUID         = "$GUID"
        }

        $Result = "Updated JIT Role Template '$($TemplateName)' (GUID: $GUID)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update JIT Role Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })
}
