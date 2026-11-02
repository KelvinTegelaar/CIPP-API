using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Management.Automation;
using System.Reflection;

namespace CIPP
{
    // Enumerating PSObject.Properties builds reserved member sets and caches that stay attached to every row (~3 KB each).
    internal static class PSMembers
    {
        private static readonly Func<object, IEnumerable<PSMemberInfo>?>? s_instanceMembers = Build();
        // Enumerating Properties once adds the reserved pstypenames to the instance members, marked hidden.
        private static readonly Func<PSMemberInfo, bool>? s_isHidden = BuildIsHidden();

        private static Func<PSMemberInfo, bool>? BuildIsHidden()
        {
            try
            {
                var property = typeof(PSMemberInfo).GetProperty("IsHidden", BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Instance);
                if (property == null || property.PropertyType != typeof(bool)) return null;
                var member = Expression.Parameter(typeof(PSMemberInfo));
                return Expression.Lambda<Func<PSMemberInfo, bool>>(Expression.Property(member, property), member).Compile();
            }
            catch { return null; }
        }

        private static Func<object, IEnumerable<PSMemberInfo>?>? Build()
        {
            try
            {
                var method = typeof(PSObject).GetMethod("HasInstanceMembers", BindingFlags.NonPublic | BindingFlags.Static);
                if (method == null) return null;
                var parameters = method.GetParameters();
                if (parameters.Length != 2 || !parameters[1].ParameterType.IsByRef) return null;
                var collectionType = parameters[1].ParameterType.GetElementType()!;
                if (!typeof(IEnumerable<PSMemberInfo>).IsAssignableFrom(collectionType)) return null;

                var obj = Expression.Parameter(typeof(object));
                var members = Expression.Variable(collectionType);
                var body = Expression.Block(new[] { members },
                    Expression.Condition(Expression.Call(method, obj, members),
                        Expression.Convert(members, typeof(IEnumerable<PSMemberInfo>)),
                        Expression.Constant(null, typeof(IEnumerable<PSMemberInfo>))));
                return Expression.Lambda<Func<object, IEnumerable<PSMemberInfo>?>>(body, obj).Compile();
            }
            catch { return null; }
        }

        public static bool Available => s_instanceMembers != null && s_isHidden != null;

        // Properties.Add minus the member copy and the type-table check (JSON records have no type data): ~1/3 faster
        private static readonly Func<string, bool>? s_isReserved = BuildIsReserved();
        private static readonly Action<PSObject, PSMemberInfo>? s_addInstance = BuildAddInstance();

        private static Func<string, bool>? BuildIsReserved()
        {
            try
            {
                var method = typeof(PSMemberInfoCollection<PSPropertyInfo>).GetMethod("IsReservedName", BindingFlags.NonPublic | BindingFlags.Static, new[] { typeof(string) });
                return method == null ? null : (Func<string, bool>)method.CreateDelegate(typeof(Func<string, bool>));
            }
            catch { return null; }
        }

        private static Action<PSObject, PSMemberInfo>? BuildAddInstance()
        {
            try
            {
                var asm = typeof(PSObject).Assembly;
                var replicate = typeof(PSMemberInfo).GetMethod("ReplicateInstance", BindingFlags.NonPublic | BindingFlags.Instance, new[] { typeof(object) });
                var instanceMembers = typeof(PSObject).GetProperty("InstanceMembers", BindingFlags.NonPublic | BindingFlags.Instance);
                var add = instanceMembers?.PropertyType.GetMethod("Add", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance, new[] { typeof(PSMemberInfo), typeof(bool) });
                var hasInstanceMember = asm.GetType("System.Management.Automation.Language.PSGetMemberBinder")?.GetMethod("SetHasInstanceMember", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static, new[] { typeof(string) });
                var noteType = asm.GetType("System.Management.Automation.Language.PSVariableAssignmentBinder")?.GetMethod("NoteTypeHasInstanceMemberOrTypeName", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static, new[] { typeof(Type) });
                if (replicate == null || instanceMembers == null || add == null || hasInstanceMember == null || noteType == null) return null;

                var pso = Expression.Parameter(typeof(PSObject));
                var member = Expression.Parameter(typeof(PSMemberInfo));
                var body = Expression.Block(
                    Expression.Call(member, replicate, Expression.Convert(pso, typeof(object))),
                    Expression.Call(Expression.Property(pso, instanceMembers), add, Expression.Convert(member, add.GetParameters()[0].ParameterType), Expression.Constant(false)),
                    Expression.Call(hasInstanceMember, Expression.Property(member, nameof(PSMemberInfo.Name))),
                    Expression.Call(noteType, Expression.Constant(typeof(PSCustomObject))));
                return Expression.Lambda<Action<PSObject, PSMemberInfo>>(body, pso, member).Compile();
            }
            catch { return null; }
        }

        /// <summary>pso.Properties.Add(new PSNoteProperty(name, value)) for a PSCustomObject being built.</summary>
        public static void AddNoteProperty(PSObject pso, string name, object? value)
        {
            var member = new PSNoteProperty(name, value);
            if (s_addInstance == null || s_isReserved == null || s_isReserved(name) || pso.BaseObject is not PSCustomObject) pso.Properties.Add(member);
            else s_addInstance(pso, member);
        }

        public static bool FastAddAvailable => s_addInstance != null && s_isReserved != null;

        // Added properties only: adapted .NET properties of a wrapped value are not included.
        public static IEnumerable<PSPropertyInfo> InstanceProperties(PSObject pso)
        {
            var members = s_instanceMembers!(pso);
            if (members == null) yield break;
            foreach (var m in members)
                if (m is PSPropertyInfo p && !s_isHidden!(p)) yield return p;
        }

        public static bool HasNoteProperty(PSObject pso)
        {
            var members = s_instanceMembers!(pso);
            if (members == null) return false;
            foreach (var m in members)
                if (m is PSNoteProperty && !s_isHidden!(m)) return true;
            return false;
        }
    }
}
