import Foundation
import SwiftUI
import Combine
import PostHog
import AppKit
import EventKit

@MainActor
class MeetingListViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""

    @Published var upcomingEvents: [EKEvent] = []

    private var cancellables = Set<AnyCancellable>()
    private let recordingSessionManager = RecordingSessionManager.shared

    // Computed property to filter meetings based on search text AND exclude upcoming calendar events
    var filteredMeetings: [Meeting] {
        // First, exclude meetings linked to upcoming calendar events
        let upcomingEventIds = Set(upcomingEvents.map { $0.eventIdentifier })
        let nonUpcomingMeetings = meetings.filter { meeting in
            guard let eventId = meeting.calendarEventId else { return true }
            return !upcomingEventIds.contains(eventId)
        }

        // Then apply search filter if search text exists
        guard !searchText.isEmpty else { return nonUpcomingMeetings }

        return nonUpcomingMeetings.filter { meeting in
            // Search in title
            meeting.title.localizedCaseInsensitiveContains(searchText) ||
            // Search in user notes
            meeting.userNotes.localizedCaseInsensitiveContains(searchText) ||
            // Search in generated notes
            meeting.generatedNotes.localizedCaseInsensitiveContains(searchText) ||
            // Search in transcript text
            meeting.transcriptChunks.contains { chunk in
                chunk.text.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    init() {
        loadMeetings()

        // Subscribe to calendar events
        CalendarManager.shared.$upcomingEvents
            .receive(on: DispatchQueue.main)
            .assign(to: &$upcomingEvents)

        // Initial fetch if enabled
        if UserDefaultsManager.shared.calendarIntegrationEnabled {
            CalendarManager.shared.fetchUpcomingEvents(calendarIDs: UserDefaultsManager.shared.selectedCalendarIDs)
        }

        // Listen for saved meeting notifications to refresh the list
        NotificationCenter.default.publisher(for: .meetingSaved)
            .sink { [weak self] notification in
                guard let self = self,
                      let savedMeeting = notification.object as? Meeting else { return }
                
                // Update the specific meeting in the list without triggering a full reload
                if let index = self.meetings.firstIndex(where: { $0.id == savedMeeting.id }) {
                    print("🔄 Updating meeting in list: \(savedMeeting.id)")
                    self.meetings[index] = savedMeeting
                } else {
                    // If meeting not in list, it might be new - reload to be safe
                    print("🔔 Meeting not found in list, reloading...")
                    self.loadMeetings()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .meetingDeleted)
            .sink { [weak self] _ in
                print("🔔 Meeting deleted notification received. Reloading meetings list...")
                self?.loadMeetings()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .meetingsDeleted)
            .sink { [weak self] _ in
                print("🔔 All meetings deleted notification received. Reloading meetings list...")
                self?.loadMeetings()
            }
            .store(in: &cancellables)

        // Listen for transcription session save requests (from mic following)
        NotificationCenter.default.publisher(for: NSNotification.Name("SaveTranscriptionSession"))
            .sink { [weak self] notification in
                if let session = notification.userInfo?["session"] as? TranscriptionSession {
                    print("🔔 Transcription session save request received")
                    self?.saveTranscriptionSession(session)
                }
            }
            .store(in: &cancellables)
    }

    func createMeeting(from event: EKEvent) -> Meeting {
        // Check if a meeting already exists for this calendar event
        if let existingMeeting = meetings.first(where: { $0.calendarEventId == event.eventIdentifier }) {
            return existingMeeting
        }

        // Create new meeting with calendar event ID
        let newMeeting = Meeting(
            title: event.title ?? "Untitled Meeting",
            calendarEventId: event.eventIdentifier
        )
        meetings.insert(newMeeting, at: 0)
        _ = LocalStorageManager.shared.saveMeeting(newMeeting)

        NSApp.activate(ignoringOtherApps: true)
        PostHogSDK.shared.capture("meeting_created_from_calendar")

        return newMeeting
    }

    func loadMeetings() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.async { [weak self] in
            let loadedMeetings = LocalStorageManager.shared.loadMeetings()
            print("📋 Loaded \(loadedMeetings.count) meetings")
            self?.meetings = loadedMeetings
            self?.isLoading = false
        }
    }

    func deleteMeeting(_ meeting: Meeting) {
        meetings.removeAll { $0.id == meeting.id }
        _ = LocalStorageManager.shared.deleteMeeting(meeting)
    }


    func createNewMeeting() -> Meeting {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, h:mm a"
        let formattedDate = dateFormatter.string(from: Date())

        // Create meeting immediately with placeholder title
        var newMeeting = Meeting(title: "Recording - \(formattedDate)")
        let meetingId = newMeeting.id // Capture ID for background task
        meetings.insert(newMeeting, at: 0)
        
        // Save immediately to prevent data loss if app terminates before background task completes
        let saveSuccess = LocalStorageManager.shared.saveMeeting(newMeeting)
        if saveSuccess {
            print("✅ Saved new meeting immediately: \(newMeeting.id)")
            NotificationCenter.default.post(name: .meetingSaved, object: newMeeting)
        } else {
            print("❌ Failed to save new meeting immediately")
        }

        // Get browser context asynchronously and update title later
        Task.detached(priority: .background) {
            if let context = BrowserURLHelper.getCurrentContext() {
                print("📱 Browser context: \(context)")
                await MainActor.run {
                    // Find and update the meeting in the array by ID
                    if let index = self.meetings.firstIndex(where: { $0.id == meetingId }) {
                        self.meetings[index].title = "\(context) - \(formattedDate)"
                        print("✅ Updated title to: \(self.meetings[index].title)")
                        // Save again with updated title
                        let success = LocalStorageManager.shared.saveMeeting(self.meetings[index])
                        if success {
                            // Post notification so MeetingViewModel can update
                            NotificationCenter.default.post(name: .meetingSaved, object: self.meetings[index])
                        }
                    }
                }
            } else {
                // Browser context lookup failed, but meeting is already saved with placeholder title
                print("ℹ️ Browser context not available, meeting saved with placeholder title")
            }
        }

        // Activate the app to bring it to focus
        NSApp.activate(ignoringOtherApps: true)

        // Track meeting creation event
        PostHogSDK.shared.capture("meeting_created")
        return newMeeting
    }

    /// Save a transcription session (e.g., from mic following mode)
    func saveTranscriptionSession(_ session: TranscriptionSession) {
        print("💾 Saving transcription session: \(session.title)")

        // Add to the list
        meetings.insert(session, at: 0)

        // Persist to disk
        _ = LocalStorageManager.shared.saveMeeting(session)

        // Track the event
        PostHogSDK.shared.capture("transcription_session_saved", properties: [
            "source": session.source.rawValue,
            "chunk_count": session.transcriptChunks.count
        ])

        print("✅ Transcription session saved successfully")
    }
}
