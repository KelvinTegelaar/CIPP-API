function ConvertTo-CIPPODataFilterValue {
    <#
    .SYNOPSIS
        Sanitizes a value for safe interpolation into an OData filter string.
    .DESCRIPTION
        Prevents OData injection by either escaping the value (String type) or
        enforcing strict format validation (Guid, Date, Integer types) before
        the value is embedded in an Azure Table Storage or Graph API $filter expression.
        Use this for all user-supplied or external values that flow into filter strings.
    .PARAMETER Value
        The input value to sanitize.
    .PARAMETER Type
        The expected data type of the value.
        - String  : Escapes single quotes by doubling them (OData spec). Safe for any string field.
        - Guid    : Validates UUID v4 format and throws if invalid.
        - Date    : Validates yyyy-MM-dd or yyyyMMdd format and throws if invalid.
        - Integer : Validates that the value is all digits and throws if invalid.
    .EXAMPLE
        $SafeRef = ConvertTo-CIPPODataFilterValue -Value $Reference -Type String
        $Filter = "PartitionKey eq 'CippQueue' and Reference eq '$SafeRef'"
    .EXAMPLE
        $SafeId = ConvertTo-CIPPODataFilterValue -Value $TenantId -Type Guid
        $Filter = "PartitionKey eq 'Tenants' and customerId eq '$SafeId'"
    .EXAMPLE
        $SafeDate = ConvertTo-CIPPODataFilterValue -Value $Request.Query.DateFilter -Type Date
        $Filter = "PartitionKey eq '$SafeDate'"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [ValidateSet('String', 'Guid', 'Date', 'Integer')]
        [string]$Type = 'String'
    )

    switch ($Type) {
        'Guid' {
            if ($Value -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                throw "Invalid GUID format for OData filter: '$Value'"
            }
            return $Value
        }
        'Date' {
            # Accepts ISO 8601: date-only (yyyy-MM-dd, yyyyMMdd) or full datetime with optional time, fractional seconds, and offset/Z
            if ($Value -notmatch '^\d{4}-?\d{2}-?\d{2}(T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?)?$') {
                throw "Invalid date format for OData filter. Expected ISO 8601 (e.g. yyyy-MM-dd or yyyy-MM-ddTHH:mm:ssZ), got: '$Value'"
            }
            return $Value
        }
        'Integer' {
            if ($Value -notmatch '^\d+$') {
                throw "Invalid integer for OData filter: '$Value'"
            }
            return $Value
        }
        default {
            # OData spec: escape single quotes by doubling them
            return $Value -replace "'", "''"
        }
    }
}
