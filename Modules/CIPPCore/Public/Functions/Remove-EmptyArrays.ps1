function Remove-EmptyArrays {
    <#
    .SYNOPSIS
        Recursively removes empty arrays and null properties from objects
    .DESCRIPTION
        This function recursively traverses an object (Array, Hashtable, or PSCustomObject) and removes:
        - Empty arrays
        - Null properties
        The function modifies the object in place.
    .PARAMETER Object
        The object to process (can be Array, Hashtable, or PSCustomObject)
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        $obj = @{ items = @(); name = "test"; value = $null }
        Remove-EmptyArrays -Object $obj
    .EXAMPLE
        $obj = [PSCustomObject]@{ items = @(); name = "test" }
        Remove-EmptyArrays -Object $obj
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object
    )

    if ($Object -is [Array]) {
        foreach ($Item in $Object) { 
            Remove-EmptyArrays -Object $Item 
        }
    } elseif ($Object -is [HashTable]) {
        foreach ($Key in @($Object.get_Keys())) {
            if ($Object[$Key] -is [Array] -and $Object[$Key].get_Count() -eq 0) {
                $Object.Remove($Key)
            } else { 
                Remove-EmptyArrays -Object $Object[$Key] 
            }
        }
    } elseif ($Object -is [PSCustomObject]) {
        foreach ($Name in @($Object.PSObject.Properties.Name)) {
            if ($Object.$Name -is [Array] -and $Object.$Name.get_Count() -eq 0) {
                $Object.PSObject.Properties.Remove($Name)
            } elseif ($null -eq $Object.$Name) {
                $Object.PSObject.Properties.Remove($Name)
            } else { 
                Remove-EmptyArrays -Object $Object.$Name 
            }
        }
    }
}
