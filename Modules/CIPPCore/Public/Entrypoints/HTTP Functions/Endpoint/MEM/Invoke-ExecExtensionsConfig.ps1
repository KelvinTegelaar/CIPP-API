function Invoke-ExecExtensionsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    
    $APIName = $Request.Params.CIPPEndpoint
    
    try {
        $ConfigTable = Get-CIPPTable -TableName 'Extensionsconfig'
        $ConfigEntity = Get-CIPPAzDataTableEntity @ConfigTable
        
        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            $Body = @{}
            $StatusCode = [HttpStatusCode]::OK
            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = $Body
                })
        }
        
        $Config = $ConfigEntity.config | ConvertFrom-Json
        
        # If List parameter is provided, return only that section
        if ($Request.Query.List) {
            $Section = $Request.Query.List
            $Body = if ($Config.$Section) {
                @{ $Section = $Config.$Section }
            } else {
                @{}
            }
        } else {
            # Return entire config
            $Body = $Config
        }
        
        $StatusCode = [HttpStatusCode]::OK
        
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Failed to retrieve extensions config: $($_.Exception.Message)" -Sev Error -LogData $ErrorMessage
        
        $Body = @{ Error = $_.Exception.Message }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
