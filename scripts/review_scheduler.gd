extends RefCounted
class_name ReviewScheduler

const ALL_DOMAINS := ""


const MAX_BOX = 4
const BOX_INTERVAL_DAYS = {
    1: 0,
    2: 2,
    3: 5,
    4: 10
}

func new_card(question_id: String, domain_id: String = "", now_day: int = 0) -> Dictionary:
    return {
        "question_id": question_id,
        "domain": domain_id,
        "box": 1,
        "last_seen_day": now_day,
        "times_seen": 0
    }

func mark(card: Dictionary, success: bool, day: int) -> Dictionary:
    var updated = card.duplicate(true)
    updated["box"] = min(MAX_BOX, int(updated.get("box", 1)) + 1) if success else 1
    updated["last_seen_day"] = day
    updated["times_seen"] = int(updated.get("times_seen", 0)) + 1
    return updated

func is_due(card: Dictionary, day: int) -> bool:
    var box = int(card.get("box", 1))
    if box <= 1:
        return true

    var interval = interval_for_box(box)
    var last_seen_day = int(card.get("last_seen_day", 0))
    return day - last_seen_day >= interval

func interval_for_box(box: int) -> int:
    return int(BOX_INTERVAL_DAYS.get(clampi(box, 1, MAX_BOX), 10))

func next_due_day(card: Dictionary) -> int:
    var box = int(card.get("box", 1))
    var last_seen_day = int(card.get("last_seen_day", 0))
    return last_seen_day + interval_for_box(box)

func days_until_due(card: Dictionary, day: int) -> int:
    return max(0, next_due_day(card) - day)

func due_cards(cards: Array, day: int, domain_id: String = ALL_DOMAINS) -> Array:
    var due: Array = []
    for card in cards:
        var matches_domain = domain_id == ALL_DOMAINS or domain_id == "" or str(card.get("domain", "")) == domain_id
        if matches_domain and is_due(card, day):
            due.append(card)
    return due

func progress_percent(cards: Array, total_cards: int) -> float:
    if total_cards <= 0:
        return 1.0
    if cards.is_empty():
        return 0.0

    var box_sum = 0
    for card in cards:
        box_sum += int(card.get("box", 1))
    return clamp(float(box_sum) / float(total_cards * MAX_BOX), 0.0, 1.0)

func ensure_cards_for_questions(existing_cards: Array, questions: Array) -> Array:
    var indexed: Dictionary = {}
    for card in existing_cards:
        if typeof(card) != TYPE_DICTIONARY:
            continue
        var existing_question_id = str(card.get("question_id", ""))
        if existing_question_id != "":
            indexed[existing_question_id] = card

    var cards: Array = []
    for question in questions:
        if typeof(question) != TYPE_DICTIONARY:
            continue
        var question_id = str(question.get("id", ""))
        if question_id == "":
            continue
        var domain_id = str(question.get("domain", ""))
        if indexed.has(question_id):
            cards.append(_normalized_existing_card(indexed[question_id], question_id, domain_id))
        else:
            cards.append(new_card(question_id, domain_id, 0))
    return cards

func _normalized_existing_card(card: Dictionary, question_id: String, domain_id: String) -> Dictionary:
    return {
        "question_id": question_id,
        "domain": domain_id,
        "box": clampi(int(card.get("box", 1)), 1, MAX_BOX),
        "last_seen_day": int(card.get("last_seen_day", 0)),
        "times_seen": max(0, int(card.get("times_seen", 0)))
    }