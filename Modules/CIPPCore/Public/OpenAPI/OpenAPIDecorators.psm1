# OpenAPI Decorators for CIPP PowerShell Functions

class OpenAPIOperation {
    [string]$Summary
    [string]$Description
    [string[]]$Tags
    [string]$OperationId
    [bool]$Deprecated

    OpenAPIOperation([string]$summary, [string]$description, [string[]]$tags) {
        $this.Summary = $summary
        $this.Description = $description
        $this.Tags = $tags
        $this.Deprecated = $false
    }
}

class OpenAPIParameter {
    [string]$Name
    [string]$In  # query, path, header, body
    [string]$Description
    [bool]$Required
    [string]$Type
    [string]$Format
    [string[]]$Enum
    [object]$Example
    [object]$Schema

    OpenAPIParameter([string]$name, [string]$in, [string]$description, [bool]$required, [string]$type) {
        $this.Name = $name
        $this.In = $in
        $this.Description = $description
        $this.Required = $required
        $this.Type = $type
    }
}

class OpenAPIResponse {
    [string]$StatusCode
    [string]$Description
    [object]$Schema
    [hashtable]$Headers

    OpenAPIResponse([string]$statusCode, [string]$description) {
        $this.StatusCode = $statusCode
        $this.Description = $description
        $this.Headers = @{}
    }
}

# Decorator functions that can be used in PowerShell function comments

function New-OpenAPIOperation {
    param(
        [string]$Summary,
        [string]$Description,
        [string[]]$Tags = @(),
        [string]$OperationId,
        [bool]$Deprecated = $false
    )
    
    return [OpenAPIOperation]::new($Summary, $Description, $Tags)
}

function New-OpenAPIParameter {
    param(
        [string]$Name,
        [ValidateSet('query', 'path', 'header', 'body')]
        [string]$In,
        [string]$Description,
        [bool]$Required = $false,
        [ValidateSet('string', 'integer', 'boolean', 'array', 'object')]
        [string]$Type = 'string',
        [string]$Format,
        [string[]]$Enum,
        [object]$Example,
        [object]$Schema
    )
    
    $param = [OpenAPIParameter]::new($Name, $In, $Description, $Required, $Type)
    if ($Format) { $param.Format = $Format }
    if ($Enum) { $param.Enum = $Enum }
    if ($Example) { $param.Example = $Example }
    if ($Schema) { $param.Schema = $Schema }
    
    return $param
}

function New-OpenAPIResponse {
    param(
        [string]$StatusCode,
        [string]$Description,
        [object]$Schema,
        [hashtable]$Headers = @{}
    )
    
    $response = [OpenAPIResponse]::new($StatusCode, $Description)
    if ($Schema) { $response.Schema = $Schema }
    if ($Headers.Count -gt 0) { $response.Headers = $Headers }
    
    return $response
}

# Export the classes and functions
Export-ModuleMember -Function New-OpenAPIOperation, New-OpenAPIParameter, New-OpenAPIResponse
Export-ModuleMember -Class OpenAPIOperation, OpenAPIParameter, OpenAPIResponse
