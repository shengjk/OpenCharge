import Foundation

/// Display-only formatting. Persisted dates and schedule calculations are unchanged.
public enum DateDisplay {
 public enum Style: CaseIterable, Sendable { case standard, abbreviated, time }
 public static func string(_ date: Date, style: Style = .standard, locale: Locale = .current,
                           calendar: Calendar = .current, timeZone: TimeZone = .current) -> String {
  if #available(macOS 12.0, *) {
   let dateStyle: Date.FormatStyle.DateStyle = style == .standard ? .numeric : style == .abbreviated ? .abbreviated : .omitted
   let timeStyle: Date.FormatStyle.TimeStyle = style == .time ? .standard : .shortened
   return date.formatted(Date.FormatStyle(date:dateStyle,time:timeStyle,locale:locale,calendar:calendar,timeZone:timeZone))
  }
  return legacy(date,style:style,locale:locale,calendar:calendar,timeZone:timeZone)
 }
 static func legacy(_ date: Date, style: Style, locale: Locale, calendar: Calendar, timeZone: TimeZone) -> String {
  let formatter = DateFormatter()
  formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = timeZone
  switch style {
  case .standard: formatter.setLocalizedDateFormatFromTemplate("yMdjm")
  case .abbreviated: formatter.dateStyle = .medium; formatter.timeStyle = .short
  case .time: formatter.dateStyle = .none; formatter.timeStyle = .medium
  }
  return formatter.string(from:date)
 }
}
