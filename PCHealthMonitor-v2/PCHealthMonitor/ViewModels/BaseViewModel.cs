using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace PCHealthMonitor.ViewModels;

/// <summary>
/// Base class for all ViewModels.
/// Implements INotifyPropertyChanged with CallerMemberName support.
/// </summary>
public abstract class BaseViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>
    /// Raises PropertyChanged for the given property name.
    /// </summary>
    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    /// <summary>
    /// Sets a backing field and raises PropertyChanged only if the value changed.
    /// Returns true if the value was changed.
    /// </summary>
    protected bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
            return false;

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    /// <summary>
    /// Sets a backing field, raises PropertyChanged, then invokes an optional callback.
    /// </summary>
    protected bool SetProperty<T>(ref T field, T value, Action? onChanged,
        [CallerMemberName] string? propertyName = null)
    {
        if (!SetProperty(ref field, value, propertyName))
            return false;

        onChanged?.Invoke();
        return true;
    }
}
