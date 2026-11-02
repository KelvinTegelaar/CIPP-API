Function Invoke-AddSensitiveInfoTypeTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitiveInfoType.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Fields kept for JSON-authored (deploy drawer) templates.
    $AllowedFields = @(
        'Name', 'Description',
        'Pattern', 'Confidence',
        'PatternsProximity', 'Locale', 'Recommended', 'PublisherName',
        'FileDataBase64'
    )

    try {
        $GUID = (New-Guid).GUID
        $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
        $Identity = $Request.Body.Identity ?? $Request.Body.Id ?? $Request.Body.Name ?? $Request.Body.name

        if ($TenantFilter -and $Identity) {
            # --- Path A: capture from an existing tenant SIT's rule pack ---
            $Sit = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationType' -Compliance |
                Where-Object { $_.Name -eq $Identity -or $_.Id -eq $Identity -or $_.Identity -eq $Identity } | Select-Object -First 1
            if (-not $Sit) {
                throw "Sensitive Information Type '$Identity' not found in tenant $TenantFilter."
            }
            if ($Sit.Publisher -like 'Microsoft*') {
                throw "SIT '$($Sit.Name)' is a Microsoft built-in and cannot be templated."
            }

            $Pack = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationTypeRulePackage' -cmdParams @{ Identity = $Sit.RulePackId } -Compliance | Select-Object -First 1
            $Xml = $Pack.ClassificationRuleCollectionXml
            if ([string]::IsNullOrWhiteSpace([string]$Xml)) {
                throw "Could not retrieve the rule pack XML for SIT '$($Sit.Name)' (pack $($Sit.RulePackId))."
            }

            # Reduce to just this SIT's entity (fingerprint SITs share the one managed pack; even regex SITs
            # get a fresh pack id so a redeploy can't collide), then store as the UTF-16 base64 bytes the
            # New-/Set-*RulePackage cmdlets expect.
            $SingleXml = Get-CIPPSitSinglePackXml -PackXml ([string]$Xml) -EntityId ([string]$Sit.Id) -EntityName ([string]$Sit.Name)
            $FileDataBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($SingleXml))

            # 'name'/'comments' drive the template list display; deploy reads $Template.Name (resolves to
            # 'name' case-insensitively), .Description, and .FileDataBase64.
            $Ordered = [ordered]@{
                name           = $Sit.Name
                comments       = $Sit.Description
                Description    = $Sit.Description
                FileDataBase64 = $FileDataBase64
            }
        } else {
            # --- Path B: JSON-authored template (simple Pattern or advanced FileDataBase64) ---
            $Source = if ($Request.Body.PowerShellCommand) {
                $Request.Body.PowerShellCommand | ConvertFrom-Json
            } else {
                [pscustomobject]$Request.Body
            }

            $Clean = [ordered]@{}
            foreach ($prop in $Source.PSObject.Properties) {
                if ($prop.Name -notin $AllowedFields) { continue }
                $val = $prop.Value
                if ($null -eq $val) { continue }
                if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
                $Clean[$prop.Name] = $val
            }

            if (-not $Clean.Contains('Pattern') -and -not $Clean.Contains('FileDataBase64')) {
                $Result = "Template requires either 'Pattern' (simple mode) or 'FileDataBase64' (advanced mode), or a tenantFilter + Identity to capture an existing SIT."
                Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Warning'
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = $Result }
                    })
            }

            $Ordered = [ordered]@{
                name     = $Clean['Name'] ?? $Source.Name ?? $Source.name
                comments = $Source.Comment ?? $Source.comments
            }
            foreach ($k in $Clean.Keys) {
                if ($Ordered.Contains($k)) { continue }
                $Ordered[$k] = $Clean[$k]
            }
        }

        $JSON = ([pscustomobject]$Ordered | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SensitiveInfoTypeTemplate'
        }
        $Result = "Successfully created Sensitive Information Type Template: $($Ordered['name']) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Sensitive Information Type Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
