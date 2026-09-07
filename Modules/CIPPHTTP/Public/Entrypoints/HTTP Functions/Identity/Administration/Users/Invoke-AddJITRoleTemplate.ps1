function Invoke-AddJITRoleTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .DESCRIPTION
        Creates a JIT Role Template - a named allow-list of directory roles that can be assigned to a
        CIPP custom role to restrict which roles that role's members may grant via JIT Admin.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TemplateName = $Request.Body.templateName

        if ([string]::IsNullOrWhiteSpace($TemplateName)) {
            throw 'templateName is required'
        }
        if (-not $Request.Body.roles -or @($Request.Body.roles).Count -eq 0) {
            throw 'At least one role is required'
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Creating JIT Role template '$TemplateName'" -Sev 'Info'

        # Get user info for audit
        $UserDetails = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

        # Check if template name already exists
        $Table = Get-CippTable -tablename 'templates'
        $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'JITRoleTemplate'"
        $ExistingNames = $ExistingTemplates | ForEach-Object {
            try {
                $data = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                if ($data.templateName -eq $TemplateName) {
                    $data
                }
            } catch {}
        }

        if ($ExistingNames) {
            throw "A JIT Role Template with name '$TemplateName' already exists"
        }

        $TemplateObject = @{
            templateName = $TemplateName
            roles        = $Request.Body.roles
            createdBy    = $UserDetails
            createdDate  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        $GUID = (New-Guid).GUID
        $JSON = ConvertTo-Json -InputObject $TemplateObject -Depth 100 -Compress

        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'JITRoleTemplate'
            GUID         = "$GUID"
        }

        $Result = "Created JIT Role Template '$($TemplateName)' with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create JIT Role Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })
}
