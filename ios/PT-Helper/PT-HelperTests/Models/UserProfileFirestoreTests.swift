import XCTest
@testable import PT_Helper

// MARK: - UserProfile Firestore Parsing Tests

final class UserProfileFirestoreTests: XCTestCase {

    // MARK: - Basic Field Parsing

    func testFromFirestore_basicFields() {
        let data: [String: Any] = [
            "userId": "user123",
            "firstName": "Jane",
            "lastName": "Smith",
            "sex": "Female",
            "heightFeet": 5,
            "heightInches": 6,
            "weight": 140.5,
            "activityLevel": "Very Active",
            "primarySport": "Soccer",
            "medicalConditions": ["Asthma", "Diabetes"]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.firstName, "Jane")
        XCTAssertEqual(profile.lastName, "Smith")
        XCTAssertEqual(profile.sex, "Female")
        XCTAssertEqual(profile.heightFeet, 5)
        XCTAssertEqual(profile.heightInches, 6)
        XCTAssertEqual(profile.weight, 140.5)
        XCTAssertEqual(profile.activityLevel, "Very Active")
        XCTAssertEqual(profile.primarySport, "Soccer")
        XCTAssertEqual(profile.medicalConditions, ["Asthma", "Diabetes"])
    }

    func testFromFirestore_missingFields_usesDefaults() {
        let data: [String: Any] = [:]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.firstName, "")
        XCTAssertEqual(profile.lastName, "")
        XCTAssertEqual(profile.sex, "")
        XCTAssertEqual(profile.heightFeet, 0)
        XCTAssertEqual(profile.heightInches, 0)
        XCTAssertEqual(profile.weight, 0.0)
        XCTAssertEqual(profile.activityLevel, "")
        XCTAssertNil(profile.primarySport)
        XCTAssertTrue(profile.medicalConditions.isEmpty)
        XCTAssertTrue(profile.surgeries.isEmpty)
        XCTAssertTrue(profile.injuries.isEmpty)
    }

    func testFromFirestore_nameFieldFallback() {
        // Old docs may have "name" instead of "firstName"
        let data: [String: Any] = [
            "name": "John"
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.firstName, "John")
    }

    func testFromFirestore_firstNameTakesPrecedenceOverName() {
        let data: [String: Any] = [
            "firstName": "Jane",
            "name": "John"
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.firstName, "Jane")
    }

    // MARK: - Medications

    func testFromFirestore_medications() {
        let data: [String: Any] = [
            "medications": ["Blood Thinners", "Beta Blockers", "Corticosteroids"]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.medications, ["Blood Thinners", "Beta Blockers", "Corticosteroids"])
    }

    func testFromFirestore_noMedications_isNil() {
        let data: [String: Any] = [:]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertNil(profile.medications)
    }

    // MARK: - Surgery Parsing

    func testFromFirestore_surgeries_allFields() {
        let surgeryId = UUID().uuidString
        let data: [String: Any] = [
            "surgeries": [
                [
                    "id": surgeryId,
                    "name": "ACL Reconstruction",
                    "year": 2023,
                    "bodyArea": "Right Knee",
                    "recoveryStatus": "Still recovering",
                    "restrictions": "No running for 6 months"
                ]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.surgeries.count, 1)
        let surgery = profile.surgeries[0]
        XCTAssertEqual(surgery.name, "ACL Reconstruction")
        XCTAssertEqual(surgery.year, 2023)
        XCTAssertEqual(surgery.bodyArea, "Right Knee")
        XCTAssertEqual(surgery.recoveryStatus, "Still recovering")
        XCTAssertEqual(surgery.restrictions, "No running for 6 months")
    }

    func testFromFirestore_surgeries_minimalFields() {
        let data: [String: Any] = [
            "surgeries": [
                ["name": "Knee Surgery", "year": 2020]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.surgeries.count, 1)
        let surgery = profile.surgeries[0]
        XCTAssertEqual(surgery.name, "Knee Surgery")
        XCTAssertEqual(surgery.year, 2020)
        XCTAssertNil(surgery.bodyArea)
        XCTAssertNil(surgery.recoveryStatus)
        XCTAssertNil(surgery.restrictions)
    }

    func testFromFirestore_surgeries_missingName_defaultsToEmpty() {
        let data: [String: Any] = [
            "surgeries": [
                ["year": 2020]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.surgeries.count, 1)
        XCTAssertEqual(profile.surgeries[0].name, "")
    }

    func testFromFirestore_multipleSurgeries() {
        let data: [String: Any] = [
            "surgeries": [
                ["name": "ACL Repair", "year": 2020],
                ["name": "Rotator Cuff", "year": 2022, "bodyArea": "Left Shoulder"]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.surgeries.count, 2)
        XCTAssertEqual(profile.surgeries[1].bodyArea, "Left Shoulder")
    }

    // MARK: - Injury Parsing

    func testFromFirestore_injuries_allFields() {
        let injuryId = UUID().uuidString
        let data: [String: Any] = [
            "injuries": [
                [
                    "id": injuryId,
                    "bodyArea": "Right Ankle",
                    "description": "Severe sprain",
                    "isCurrent": true,
                    "year": 2025,
                    "sawDoctor": true,
                    "hadPhysicalTherapy": false,
                    "recoveryStatus": "Still dealing with it"
                ]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.injuries.count, 1)
        let injury = profile.injuries[0]
        XCTAssertEqual(injury.bodyArea, "Right Ankle")
        XCTAssertEqual(injury.description, "Severe sprain")
        XCTAssertTrue(injury.isCurrent)
        XCTAssertEqual(injury.year, 2025)
        XCTAssertEqual(injury.sawDoctor, true)
        XCTAssertEqual(injury.hadPhysicalTherapy, false)
        XCTAssertEqual(injury.recoveryStatus, "Still dealing with it")
    }

    func testFromFirestore_injuries_minimalFields() {
        let data: [String: Any] = [
            "injuries": [
                ["bodyArea": "Left Knee", "description": "Old tear", "isCurrent": false]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.injuries.count, 1)
        let injury = profile.injuries[0]
        XCTAssertEqual(injury.bodyArea, "Left Knee")
        XCTAssertFalse(injury.isCurrent)
        XCTAssertNil(injury.year)
        XCTAssertNil(injury.sawDoctor)
        XCTAssertNil(injury.hadPhysicalTherapy)
        XCTAssertNil(injury.recoveryStatus)
    }

    func testFromFirestore_injuries_missingFields_defaults() {
        let data: [String: Any] = [
            "injuries": [
                [:]  // completely empty injury entry
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.injuries.count, 1)
        XCTAssertEqual(profile.injuries[0].bodyArea, "")
        XCTAssertEqual(profile.injuries[0].description, "")
        XCTAssertFalse(profile.injuries[0].isCurrent)
    }

    // MARK: - Computed Properties

    func testName_fullName() {
        let data: [String: Any] = [
            "firstName": "Jane",
            "lastName": "Smith"
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.name, "Jane Smith")
    }

    func testName_firstNameOnly() {
        let data: [String: Any] = [
            "firstName": "Jane",
            "lastName": ""
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.name, "Jane")
    }

    func testName_emptyBoth() {
        let data: [String: Any] = [:]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.name, "")
    }

    // MARK: - UUID Parsing

    func testFromFirestore_validSurgeryUUID_preserved() {
        let uuid = UUID()
        let data: [String: Any] = [
            "surgeries": [
                ["id": uuid.uuidString, "name": "Test", "year": 2024]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.surgeries[0].id, uuid)
    }

    func testFromFirestore_invalidSurgeryUUID_generatesNew() {
        let data: [String: Any] = [
            "surgeries": [
                ["id": "not-a-uuid", "name": "Test", "year": 2024]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        // Should get a new UUID, not crash
        XCTAssertNotNil(profile.surgeries[0].id)
    }

    func testFromFirestore_missingSurgeryUUID_generatesNew() {
        let data: [String: Any] = [
            "surgeries": [
                ["name": "Test", "year": 2024]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertNotNil(profile.surgeries[0].id)
    }

    // MARK: - Dominant Side

    func testFromFirestore_dominantSide() {
        let data: [String: Any] = [
            "dominantSide": "Right"
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.dominantSide, "Right")
    }

    func testFromFirestore_noDominantSide_isNil() {
        let data: [String: Any] = [:]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertNil(profile.dominantSide)
    }

    // MARK: - Surgery Extended Fields

    func testFromFirestore_surgery_extendedFields() {
        let data: [String: Any] = [
            "surgeries": [
                [
                    "name": "ACL Reconstruction",
                    "year": 2023,
                    "bodyArea": "Right Knee",
                    "surgeryType": "Arthroscopic ACL repair with hamstring graft",
                    "causingInjury": "Torn ACL from basketball",
                    "hasHardware": true,
                    "hardwareDetails": "Two titanium screws in right knee"
                ]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.surgeries.count, 1)
        let surgery = profile.surgeries[0]
        XCTAssertEqual(surgery.surgeryType, "Arthroscopic ACL repair with hamstring graft")
        XCTAssertEqual(surgery.causingInjury, "Torn ACL from basketball")
        XCTAssertEqual(surgery.hasHardware, true)
        XCTAssertEqual(surgery.hardwareDetails, "Two titanium screws in right knee")
    }

    func testFromFirestore_surgery_noExtendedFields_nilDefaults() {
        let data: [String: Any] = [
            "surgeries": [
                ["name": "Knee Surgery", "year": 2020]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        let surgery = profile.surgeries[0]
        XCTAssertNil(surgery.surgeryType)
        XCTAssertNil(surgery.causingInjury)
        XCTAssertNil(surgery.hasHardware)
        XCTAssertNil(surgery.hardwareDetails)
    }

    func testFromFirestore_surgery_hardwareFalse() {
        let data: [String: Any] = [
            "surgeries": [
                ["name": "Meniscus Repair", "year": 2022, "hasHardware": false]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.surgeries[0].hasHardware, false)
        XCTAssertNil(profile.surgeries[0].hardwareDetails)
    }

    // MARK: - Medication History

    func testFromFirestore_medicationHistory() {
        let data: [String: Any] = [
            "medicationHistory": [
                [
                    "medication": "Ibuprofen",
                    "action": "started",
                    "date": "2024-06-15T10:00:00Z"
                ],
                [
                    "medication": "Blood Thinners",
                    "action": "stopped",
                    "date": "2024-07-01T08:30:00Z"
                ]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertNotNil(profile.medicationHistory)
        XCTAssertEqual(profile.medicationHistory?.count, 2)
        XCTAssertEqual(profile.medicationHistory?[0].medication, "Ibuprofen")
        XCTAssertEqual(profile.medicationHistory?[0].action, "started")
        XCTAssertEqual(profile.medicationHistory?[1].medication, "Blood Thinners")
        XCTAssertEqual(profile.medicationHistory?[1].action, "stopped")
    }

    func testFromFirestore_noMedicationHistory_isNil() {
        let data: [String: Any] = [:]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertNil(profile.medicationHistory)
    }

    func testFromFirestore_medicationHistory_invalidEntries_skipped() {
        let data: [String: Any] = [
            "medicationHistory": [
                ["medication": "Valid Med", "action": "started", "date": "2024-01-01T00:00:00Z"],
                ["invalid": "entry"],  // missing required fields
                ["medication": "Another", "action": "stopped", "date": "2024-02-01T00:00:00Z"]
            ]
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.medicationHistory?.count, 2, "Invalid entries should be skipped via compactMap")
    }

    // MARK: - Backward Compatibility

    func testFromFirestore_oldDocWithoutNewFields_loadsFine() {
        // Simulates a document created before the health history enrichment
        let data: [String: Any] = [
            "userId": "old_user",
            "firstName": "Old",
            "lastName": "User",
            "sex": "Male",
            "heightFeet": 6,
            "heightInches": 0,
            "weight": 180.0,
            "medicalConditions": ["None"],
            "surgeries": [
                ["name": "Knee Scope", "year": 2019]
            ],
            "injuries": [
                ["bodyArea": "Back", "description": "Strain", "isCurrent": false]
            ],
            "activityLevel": "Active"
        ]

        let profile = UserProfile.from(firestoreData: data)

        XCTAssertEqual(profile.firstName, "Old")
        XCTAssertNil(profile.medications)
        XCTAssertNil(profile.dominantSide)
        XCTAssertNil(profile.medicationHistory)
        XCTAssertNil(profile.surgeries[0].bodyArea)
        XCTAssertNil(profile.surgeries[0].recoveryStatus)
        XCTAssertNil(profile.surgeries[0].surgeryType)
        XCTAssertNil(profile.surgeries[0].causingInjury)
        XCTAssertNil(profile.surgeries[0].hasHardware)
        XCTAssertNil(profile.surgeries[0].hardwareDetails)
        XCTAssertNil(profile.injuries[0].year)
        XCTAssertNil(profile.injuries[0].sawDoctor)
        XCTAssertNil(profile.injuries[0].hadPhysicalTherapy)
        XCTAssertNil(profile.injuries[0].recoveryStatus)
    }
}
