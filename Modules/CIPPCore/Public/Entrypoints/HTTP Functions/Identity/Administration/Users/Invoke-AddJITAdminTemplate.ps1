function Invoke-AddJITAdminTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        # Extract data from request body
        $TenantFilter = $Request.Body.tenantFilter
        $TemplateName = $Request.Body.templateName

        # Validate required fields
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            throw 'tenantFilter is required'
        }
        if ([string]::IsNullOrWhiteSpace($TemplateName)) {
            throw 'templateName is required'
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Creating JIT Admin template '$TemplateName' for tenant: $TenantFilter" -Sev 'Info'

        # Get user info for audit
        $UserDetails = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

        # Check if template name already exists for this tenant
        $Table = Get-CippTable -tablename 'templates'
        $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'JITAdminTemplate'"
        $ExistingNames = $ExistingTemplates | ForEach-Object {
            try {
                $data = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                if ($data.tenantFilter -eq $TenantFilter -and $data.templateName -eq $TemplateName) {
                    $data
                }
            } catch {}
        }

        if ($ExistingNames) {
            throw "A template with name '$TemplateName' already exists for tenant '$TenantFilter'"
        }

        $DefaultForTenant = [bool]$Request.Body.defaultForTenant

        # If this template is set as default, unset other defaults for this tenant
        if ($DefaultForTenant) {
            $ExistingTemplates | ForEach-Object {
                try {
                    $row = $_
                    $data = $row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                    if ($data.tenantFilter -eq $TenantFilter -and $data.defaultForTenant -eq $true) {
                        # Unset the default flag
                        $data.defaultForTenant = $false
                        $row.JSON = ($data | ConvertTo-Json -Depth 100 -Compress)
                        Add-CIPPAzDataTableEntity @Table -Entity $row -Force
                        Write-LogMessage -headers $Headers -API $APIName -message "Unset default flag for existing template: $($data.templateName)" -Sev 'Info'
                    }
                } catch {
                    Write-LogMessage -headers $Headers -API $APIName -message "Failed to update existing template: $($_.Exception.Message)" -Sev 'Warning'
                }
            }
        }

        # Validate user action fields
        $DefaultUserAction = $Request.Body.defaultUserAction
        if ($TenantFilter -eq 'AllTenants' -and $DefaultUserAction -eq 'select') {
            throw 'defaultUserAction cannot be "select" when tenantFilter is "AllTenants"'
        }

        # Create template object
        $TemplateObject = @{
            tenantFilter                = $TenantFilter
            templateName                = $TemplateName
            defaultForTenant            = $DefaultForTenant
            defaultRoles                = $Request.Body.defaultRoles
            defaultDuration             = $Request.Body.defaultDuration
            defaultExpireAction         = $Request.Body.defaultExpireAction
            defaultNotificationActions  = $Request.Body.defaultNotificationActions
            generateTAPByDefault        = [bool]$Request.Body.generateTAPByDefault
            reasonTemplate              = $Request.Body.reasonTemplate
            createdBy                   = $UserDetails
            createdDate                 = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        # Add defaultUserAction if provided
        if (![string]::IsNullOrWhiteSpace($DefaultUserAction)) {
            $TemplateObject.defaultUserAction = $DefaultUserAction
        }

        # Add user detail fields when "create" action is specified
        if ($DefaultUserAction -eq 'create') {
            # These fields can be saved for both AllTenants and specific tenant templates
            if (![string]::IsNullOrWhiteSpace($Request.Body.defaultFirstName)) {
                $TemplateObject.defaultFirstName = $Request.Body.defaultFirstName
            }
            if (![string]::IsNullOrWhiteSpace($Request.Body.defaultLastName)) {
                $TemplateObject.defaultLastName = $Request.Body.defaultLastName
            }
            if (![string]::IsNullOrWhiteSpace($Request.Body.defaultUserName)) {
                $TemplateObject.defaultUserName = $Request.Body.defaultUserName
            }
            
            # defaultDomain is only saved for specific tenant templates (not AllTenants)
            if ($TenantFilter -ne 'AllTenants' -and $Request.Body.defaultDomain) {
                if ($Request.Body.defaultDomain -is [string]) {
                    if (![string]::IsNullOrWhiteSpace($Request.Body.defaultDomain)) {
                        $TemplateObject.defaultDomain = $Request.Body.defaultDomain
                    }
                } else {
                    $TemplateObject.defaultDomain = $Request.Body.defaultDomain
                }
            }
        }

        # Generate GUID for the template
        $GUID = (New-Guid).GUID

        # Convert to JSON
        $JSON = ConvertTo-Json -InputObject $TemplateObject -Depth 100 -Compress

        # Store in table
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'JITAdminTemplate'
            GUID         = "$GUID"
        }

        $Result = "Created JIT Admin Template '$($TemplateName)' with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create JIT Admin Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = "$Result" }
        })
}
