
## ----------------------------------------------------------------------------
## Convert Serialized hastable to Object (recursive)
## ----------------------------------------------------------------------------
function Convert-ObjectToHashtable {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    Param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
    process {
        # Return null if the input is null. This can happen when calling the function
        # recursively and a property is null
        if ($null -eq $InputObject) {
            return $null
        }

        # Check if the input is an array or collection. If so, we also need to convert
        # those types into hash tables as well. This function will convert all child
        # objects into hash tables (if applicable)
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) {
                    Convert-ObjectToHashtable -InputObject $object
                }
            )
            # Return the array but don't enumerate it because the object
            # may be pretty complex
            Write-Output $collection -NoEnumerate

        } elseif ($InputObject -is [psobject]) {
            # If the object has properties that need enumeration
            # Convert it to its own hash table and return it
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = Convert-ObjectToHashtable -InputObject $property.Value
            }
            $hash
        } else {
            # If the object isn't an array, collection, or other object, it's already a hash table
            # So just return it.
            $InputObject
        }
    }
}