function Invoke-AddDefenderTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TemplateName = $Request.Body.templateName
    if (-not $TemplateName) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'A template name prefix is required.' }
            })
    }

    $PolicySettings = $Request.Body.Policy
    $DefenderExclusions = $Request.Body.Exclusion
    $ASR = $Request.Body.ASR
    $EDR = $Request.Body.EDR
    $Package = [string]$Request.Body.package

    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true

    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        if ($PolicySettings) {
            $GUID = (New-Guid).GUID
            $PolicyJson = Set-CIPPDefenderAVPolicy -PolicySettings $PolicySettings -TemplateOnly
            $Object = [PSCustomObject]@{
                Displayname      = '{0} - AV Policy' -f $TemplateName
                Description      = ''
                RAWJson          = (ConvertTo-Json -Depth 15 -Compress -InputObject $PolicyJson)
                Type             = 'Catalog'
                GUID             = $GUID
                ReusableSettings = @()
            } | ConvertTo-Json -Compress
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$Object"
                RowKey       = "$GUID"
                PartitionKey = 'IntuneTemplate'
                GUID         = "$GUID"
                Package      = $Package
            }
            $Results.Add('Successfully created AV Policy template')
            Write-LogMessage -headers $Headers -API $APIName -message ("Created Defender AV Policy template '{0} - AV Policy'" -f $TemplateName) -Sev 'Info'
        }

        if ($ASR) {
            $GUID = (New-Guid).GUID
            $AsrJson = Set-CIPPDefenderASRPolicy -ASR $ASR -TemplateOnly
            $Object = [PSCustomObject]@{
                Displayname      = '{0} - ASR Policy' -f $TemplateName
                Description      = ''
                RAWJson          = (ConvertTo-Json -Depth 15 -Compress -InputObject $AsrJson)
                Type             = 'Catalog'
                GUID             = $GUID
                ReusableSettings = @()
            } | ConvertTo-Json -Compress
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$Object"
                RowKey       = "$GUID"
                PartitionKey = 'IntuneTemplate'
                GUID         = "$GUID"
                Package      = $Package
            }
            $Results.Add('Successfully created ASR Policy template')
            Write-LogMessage -headers $Headers -API $APIName -message ("Created Defender ASR Policy template '{0} - ASR Policy'" -f $TemplateName) -Sev 'Info'
        }

        if ($EDR) {
            $GUID = (New-Guid).GUID
            $EdrJson = Set-CIPPDefenderEDRPolicy -EDR $EDR -TemplateOnly
            if ($EdrJson) {
                $Object = [PSCustomObject]@{
                    Displayname      = '{0} - EDR Policy' -f $TemplateName
                    Description      = ''
                    RAWJson          = (ConvertTo-Json -Depth 15 -Compress -InputObject $EdrJson)
                    Type             = 'Catalog'
                    GUID             = $GUID
                    ReusableSettings = @()
                } | ConvertTo-Json -Compress
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    JSON         = "$Object"
                    RowKey       = "$GUID"
                    PartitionKey = 'IntuneTemplate'
                    GUID         = "$GUID"
                    Package      = $Package
                }
                $Results.Add('Successfully created EDR Policy template')
                Write-LogMessage -headers $Headers -API $APIName -message ("Created Defender EDR Policy template '{0} - EDR Policy'" -f $TemplateName) -Sev 'Info'
            }
        }

        if ($DefenderExclusions) {
            $GUID = (New-Guid).GUID
            $ExclusionJson = Set-CIPPDefenderExclusionPolicy -DefenderExclusions $DefenderExclusions -TemplateOnly
            if ($ExclusionJson) {
                $Object = [PSCustomObject]@{
                    Displayname      = '{0} - AV Exclusion Policy' -f $TemplateName
                    Description      = ''
                    RAWJson          = (ConvertTo-Json -Depth 15 -Compress -InputObject $ExclusionJson)
                    Type             = 'Catalog'
                    GUID             = $GUID
                    ReusableSettings = @()
                } | ConvertTo-Json -Compress
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    JSON         = "$Object"
                    RowKey       = "$GUID"
                    PartitionKey = 'IntuneTemplate'
                    GUID         = "$GUID"
                    Package      = $Package
                }
                $Results.Add('Successfully created AV Exclusion Policy template')
                Write-LogMessage -headers $Headers -API $APIName -message ("Created Defender AV Exclusion Policy template '{0} - AV Exclusion Policy'" -f $TemplateName) -Sev 'Info'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $FullError = "Failed to create template: $($ErrorMessage.NormalizedMessage) | $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber) | $($_.Exception.GetType().FullName)"
        $Results.Add($FullError)
        Write-LogMessage -headers $Headers -API $APIName -message $FullError -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = @($Results) }
        })
}
