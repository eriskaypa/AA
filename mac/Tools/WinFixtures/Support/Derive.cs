// Derived Mac expectations (spec 01 GF.4.4 `macExpectation: divergent`). The generator never guesses the Mac's
// output: it derives it from the Windows code by the rule the spec mandates, e.g. "treat JSON null as the default"
// (01 §4.1.10) = remove the member and let Windows load it; "preserve nested unknown members" (01 DATA-024) = the
// Windows output with every nested unknown member re-appended at the end of its object, in input order.
using System.Collections;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using AA.Models;

namespace WinFixtures;

internal static partial class Derive
{
    [GeneratedRegex(@"%%(NEWGUID|GUIDN):\d+%%")]
    private static partial Regex NumberedToken();

    /// <summary>Equality of two masked texts ignoring the numbering of GUID tokens (each text numbers its own
    /// fresh ids).</summary>
    public static bool SameModuloTokens(string a, string b) =>
        NumberedToken().Replace(a, "%%$1%%") == NumberedToken().Replace(b, "%%$1%%");

    /// <summary>01 DATA-024 superset: the Windows output plus every nested unknown member of the input (a member
    /// that is not a serialisable property of the model type at that position), appended at the end of its object in
    /// input order. Top-level and Ui unknowns are already preserved by Windows (JsonExtensionData).</summary>
    public static string MacSuperset(string input, string windowsOutput)
    {
        var outRoot = JsonNode.Parse(windowsOutput)!;
        // Re-serialising must be byte-faithful for the untouched parts, or the derivation would invent differences.
        if (outRoot.ToJsonString() != windowsOutput)
            throw new InvalidOperationException("JsonNode does not round-trip the Windows output byte-for-byte");
        using var doc = JsonDocument.Parse(input, new JsonDocumentOptions { AllowTrailingCommas = false });
        Walk(doc.RootElement, outRoot, typeof(AppData), isRoot: true);
        return outRoot.ToJsonString();
    }

    private static void Walk(JsonElement input, JsonNode? output, Type type, bool isRoot)
    {
        if (output == null) return;
        if (input.ValueKind == JsonValueKind.Object && output is JsonObject outObj)
        {
            if (typeof(IDictionary).IsAssignableFrom(type)) return;      // dictionary keys are data, not members
            var props = SerializableProperties(type);
            bool hasExtension = type.GetProperties().Any(p => p.GetCustomAttribute<JsonExtensionDataAttribute>() != null);
            foreach (var p in input.EnumerateObject())
            {
                if (props.TryGetValue(p.Name, out var propType))
                {
                    if (outObj[p.Name] is JsonNode child && p.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
                        Walk(p.Value, child, propType, isRoot: false);
                    continue;
                }
                if (isRoot || hasExtension) continue;                 // Windows keeps these itself
                if (!outObj.ContainsKey(p.Name)) outObj[p.Name] = JsonNode.Parse(p.Value.GetRawText());
            }
        }
        else if (input.ValueKind == JsonValueKind.Array && output is JsonArray outArr)
        {
            var element = ElementType(type);
            if (element == null) return;
            int i = 0;
            foreach (var item in input.EnumerateArray())
            {
                if (i >= outArr.Count) break;
                if (item.ValueKind is JsonValueKind.Object or JsonValueKind.Array) Walk(item, outArr[i], element, isRoot: false);
                i++;
            }
        }
    }

    /// <summary>Public instance properties STJ reads for <paramref name="t"/> (case-sensitive names, Opts has no
    /// case-insensitivity), excluding [JsonIgnore] and the extension-data dictionary.</summary>
    private static Dictionary<string, Type> SerializableProperties(Type t)
    {
        var map = new Dictionary<string, Type>(StringComparer.Ordinal);
        foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (p.GetIndexParameters().Length > 0) continue;
            if (p.GetCustomAttribute<JsonIgnoreAttribute>()?.Condition == JsonIgnoreCondition.Always) continue;
            if (p.GetCustomAttribute<JsonExtensionDataAttribute>() != null) continue;
            if (!p.CanWrite && !typeof(IEnumerable).IsAssignableFrom(p.PropertyType)) continue;
            var name = p.GetCustomAttribute<JsonPropertyNameAttribute>()?.Name ?? p.Name;
            map[name] = p.PropertyType;
        }
        return map;
    }

    private static Type? ElementType(Type t)
    {
        if (t.IsArray) return t.GetElementType();
        if (t.IsGenericType)
        {
            var args = t.GetGenericArguments();
            if (args.Length == 1) return args[0];
        }
        foreach (var i in t.GetInterfaces())
            if (i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IEnumerable<>)) return i.GetGenericArguments()[0];
        return null;
    }
}
