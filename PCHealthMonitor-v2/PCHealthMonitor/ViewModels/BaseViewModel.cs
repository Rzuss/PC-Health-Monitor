using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;

namespace PCHealthMonitor.ViewModels;

/// <summary>
/// Base class for all ViewModels.
/// Implements INotifyPropertyChanged and provides a UI-thread dispatch helper.
/// </summary>
public abstract class BaseViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        // Always marshal PropertyChanged to the UI thread so bindings never crash
        if (Application.Current?.Dispatcher.CheckAccess() == false)
            Application.Current.Dispatcher.BeginInvoke(
                () => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName)));
        else
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    protected bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    protected bool SetProperty<T>(ref T field, T value, Action? onChanged,
        [CallerMemberName] string? propertyName = null)
    {
        if (!SetProperty(ref field, value, propertyName)) return false;
        onChanged?.Invoke();
        return true;
    }

    /// <summary>
    /// Runs <paramref name="action"/> on the UI thread.
    /// Call this before any ObservableCollection.Add() / .Clear() from a background task.
    /// </summary>
    protected static void OnUI(Action action)
    {
        if (Application.Current?.Dispatcher.CheckAccess() == true)
            action();
        else
            Application.Current?.Dispatcher.BeginInvoke(action);
    }
}
