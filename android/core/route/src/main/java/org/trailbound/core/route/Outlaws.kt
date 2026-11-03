package org.trailbound.core.route

/** Card rarity, from the street-level operators up to the one boss card. */
enum class Rarity(val label: String) { RARE("RARE"), EPIC("EPIC"), LEGENDARY("LEGENDARY"), BOSS("BOSS") }

/**
 * A collectible outlaw card. The biography and its connection to walking are real history; the step target and
 * rarity are game mechanics. Collected the moment true lifetime steps reach [steps].
 */
data class OutlawCard(
    val name: String,
    val collection: String,
    val rarity: Rarity,
    val steps: Long,
    val quote: String,
)

/**
 * OUTLAWS ON FOOT: the endgame. Every card sits past the Silk Road at its real length (6,400 km, about
 * 8.5M steps at a 0.75 m stride), so collecting them means walking the world and then some.
 * Only people who have died; facts kept to well-documented history; DRAFT pending historian review.
 */
object Outlaws {
    const val VOL_1 = "OUTLAWS ON FOOT · Vol I: The Roads They Took"
    const val VOL_2 = "OUTLAWS ON FOOT · Vol II: The Dry Years"

    private fun outlaw(
        id: String, title: String, subtitle: String, card: OutlawCard,
        teaser: String, facts: List<String>, why: String,
    ) = Journey(
        id = id, title = title, subtitle = subtitle,
        km = (card.steps * RouteRepository.DEFAULT_STRIDE_M / 1000).toInt(), postcards = 1,
        teaser = teaser, unlock = "%,d lifetime steps".format(card.steps),
        facts = facts, why = why, card = card,
    )

    val all: List<Journey> = listOf(
        // ---- Vol I · The Footpads: city streets ----
        outlaw(
            "outlaw-moll", "The Cutpurse", "Mary Frith, \"Moll Cutpurse\" · London, c. 1584–1659",
            OutlawCard("Moll Cutpurse", VOL_1, Rarity.RARE, 9_000_000, "The crowd conceals everything."),
            teaser = "Pickpocket, fence and the most talked-about woman in Jacobean London's underworld.",
            facts = listOf(
                "c. 1584: Mary Frith is born in London.",
                "She works the crowded streets as a cutpurse, then runs a business returning stolen goods to their owners, for a fee.",
                "She walks the city in men's clothing, scandalous at the time.",
                "1611: Middleton and Dekker put her on stage in the play The Roaring Girl.",
                "1612: Made to do public penance at St Paul's Cross.",
                "1659: Dies in London.",
            ),
            why = "A life lived on foot in packed streets, reading crowds the way we read networks.",
        ),
        outlaw(
            "outlaw-lustig", "The Con Artist", "\"Count\" Victor Lustig · Paris & New York, 1890–1947",
            OutlawCard("Victor Lustig", VOL_1, Rarity.RARE, 9_500_000, "Sell them the tower."),
            teaser = "The man who sold the Eiffel Tower to a scrap dealer, then walked out of a federal jail.",
            facts = listOf(
                "1890: Born in Austria-Hungary.",
                "1925: Posing as a French official, he 'sells' the Eiffel Tower for scrap to a dealer who is too embarrassed to report it.",
                "He also cons Al Capone, and later runs a large counterfeiting operation.",
                "Sept 1935: Escapes the Federal Detention Headquarters in Manhattan down a rope of bedsheets, reportedly posing as a window washer.",
                "Caught in Pittsburgh about a month later; dies in federal custody in 1947.",
            ),
            why = "Social engineering, decades before the word. And one very public walk away.",
        ),
        outlaw(
            "outlaw-peruggia", "The Ghost of the Louvre", "Vincenzo Peruggia · Paris, 1911",
            OutlawCard("Vincenzo Peruggia", VOL_1, Rarity.EPIC, 10_000_000, "The greatest escape can look ordinary."),
            teaser = "Art thief. He walked out of the Louvre with the Mona Lisa under his work smock.",
            facts = listOf(
                "Aug 21, 1911: On a Monday, when the Louvre is closed, Peruggia, a former museum worker, takes the Mona Lisa off the wall.",
                "Dressed like the museum's workmen, he hides the panel under his smock and walks out.",
                "The painting sits in his Paris room for more than two years.",
                "Dec 1913: Arrested in Florence trying to sell it; the painting goes home to the Louvre.",
                "He serves only months in prison and is seen as a patriot by some Italians.",
            ),
            why = "No disguise beats looking like you belong there.",
        ),
        outlaw(
            "outlaw-vanmeegeren", "The Master Forger", "Han van Meegeren · Netherlands, 1889–1947",
            OutlawCard("Han van Meegeren", VOL_1, Rarity.EPIC, 10_500_000, "Paint your way out."),
            teaser = "He forged Vermeers so well that one hung in Hermann Göring's collection.",
            facts = listOf(
                "1889: Born in Deventer, Netherlands.",
                "1930s–40s: Paints fake Vermeers that fool leading experts and sell for fortunes.",
                "One, Christ and the Adulteress, is bought by Nazi leader Hermann Göring.",
                "1945: Arrested for treason for selling a national treasure to the Nazis.",
                "To prove it was a fake, he paints another 'Vermeer' in front of witnesses.",
                "1947: Convicted of forgery instead; dies weeks later.",
            ),
            why = "Proof of work, literally. The card for anyone who has had to prove what's real.",
        ),
        outlaw(
            "outlaw-sheppard", "The Escapist", "Jack Sheppard · London, 1702–1724",
            OutlawCard("Jack Sheppard", VOL_1, Rarity.LEGENDARY, 11_000_000, "No wall holds forever."),
            teaser = "Four escapes in one year, twice out of Newgate, the most secure prison in London.",
            facts = listOf(
                "1702: Born in Spitalfields, London; apprenticed as a carpenter.",
                "1724: Arrested for theft and burglary, he escapes custody four times in a single year.",
                "Oct 1724: Chained in Newgate's strongest room, he climbs up a chimney and out across the rooftops.",
                "Recaptured days later, drunk, walking the city in fine clothes.",
                "Nov 16, 1724: Hanged at Tyburn, before a crowd reported at 200,000.",
            ),
            why = "Every lock is a puzzle. He kept walking out until they stopped him for good.",
        ),
        // ---- Vol I · The Smugglers: coast paths ----
        outlaw(
            "outlaw-rattenbury", "The Coast Runner", "Jack Rattenbury · Beer, Devon, 1778–1844",
            OutlawCard("Jack Rattenbury", VOL_1, Rarity.RARE, 12_000_000, "Leave nothing for the tide."),
            teaser = "The \"Rob Roy of the West\": smuggler, pilot and fisherman on the Devon cliffs.",
            facts = listOf(
                "1778: Born in the fishing village of Beer, Devon.",
                "Goes to sea at 9; starts smuggling at about 16.",
                "Contraband is hidden in places like the Beer Quarry Caves, out of sight of the excise men.",
                "Caught and escaped many times, by his own account.",
                "1837: Dictates Memoirs of a Smuggler; buried in Seaton churchyard in 1844.",
            ),
            why = "Cliff paths at night, carrying what the government said you couldn't.",
        ),
        outlaw(
            "outlaw-gulliver", "The Smuggler King", "Isaac Gulliver · Dorset, 1745–1822",
            OutlawCard("Isaac Gulliver", VOL_1, Rarity.LEGENDARY, 13_000_000, "The coast keeps its secrets."),
            teaser = "Ran one of the largest contraband networks on England's south coast, and died rich.",
            facts = listOf(
                "1745: Born in Wiltshire.",
                "Builds a smuggling operation moving tea, gin and lace through Dorset's coast and inland routes.",
                "Reputed never to have killed anyone: the \"gentle smuggler\".",
                "Later a respected landowner and banker; dies in Wimborne in 1822.",
            ),
            why = "A whole network of paths and trusted couriers: the original distributed system.",
        ),
        // ---- Vol I · The Last Stand ----
        outlaw(
            "outlaw-kelly", "The Iron Walker", "Ned Kelly · Victoria, Australia, 1854–1880",
            OutlawCard("Ned Kelly", VOL_1, Rarity.LEGENDARY, 14_000_000, "Every step carries its weight."),
            teaser = "At his last stand he walked toward the police in about 40 kg of homemade iron armour.",
            facts = listOf(
                "1854: Born in Victoria to an Irish convict father.",
                "1878–1880: The Kelly Gang robs banks while the colony hunts them.",
                "June 28, 1880: At Glenrowan, Kelly advances on foot at dawn in plough-steel armour.",
                "Shot in his unprotected legs, he is captured.",
                "Nov 11, 1880: Hanged at Melbourne Gaol.",
            ),
            why = "The heaviest walk on the list. Some steps cost more than others.",
        ),
        // ---- Vol II · The Dry Years (Prohibition, 1920–1933) ----
        outlaw(
            "outlaw-bailey", "The Mountain Queen", "Maggie Bailey · Harlan County, Kentucky, 1904–2005",
            OutlawCard("Maggie Bailey", VOL_2, Rarity.RARE, 15_000_000, "The mountain keeps its customers."),
            teaser = "Sold moonshine from her mountain home for about 80 years.",
            facts = listOf(
                "1904: Born in Harlan County, Kentucky.",
                "Starts selling moonshine at 17, in a dry county, and keeps going into her 90s.",
                "Taken to court again and again; only one federal conviction, in 1941.",
                "Dec 2005: Dies at 101, \"Queen of the Mountain Bootleggers\".",
            ),
            why = "Appalachian hollows were walked, not driven.",
        ),
        outlaw(
            "outlaw-lythgoe", "The Bahamas Queen", "Gertrude \"Cleo\" Lythgoe · Nassau, 1888–1974",
            OutlawCard("Gertrude Lythgoe", VOL_2, Rarity.EPIC, 16_000_000, "Beyond the three-mile line."),
            teaser = "The only woman with a wholesale liquor licence in Nassau, supplying Rum Row.",
            facts = listOf(
                "1888: Born in Ohio.",
                "1920s: Runs a liquor export business from Nassau in the Bahamas, legally, just out of US reach.",
                "Her stock supplies the rum-runners anchored off the US coast: Rum Row.",
                "1964: Publishes her memoir, The Bahama Queen. Dies in 1974.",
            ),
            why = "Jurisdiction is a map. She stood on the right side of the line.",
        ),
        outlaw(
            "outlaw-mccoy", "The Real McCoy", "Bill McCoy · Atlantic Coast, 1877–1948",
            OutlawCard("Bill McCoy", VOL_2, Rarity.EPIC, 17_000_000, "Beyond the law's horizon."),
            teaser = "Pioneer of Rum Row: ships full of liquor parked just past US waters.",
            facts = listOf(
                "1877: Born in Syracuse, New York.",
                "1920s: Sails his schooner Arethusa (later Tomoka) loaded with whiskey to the edge of US waters.",
                "Known for never watering down his liquor; the phrase \"the real McCoy\" is often tied to him, though it is older.",
                "1923: His ship is seized by the Coast Guard; he serves nine months.",
            ),
            why = "Honest goods in a dishonest trade. Reputation was the only trust layer.",
        ),
        outlaw(
            "outlaw-shore-runner", "The Shore Runner", "Long Island Rum Row · 1920s · historical archetype",
            OutlawCard("The Shore Runner", VOL_2, Rarity.RARE, 18_000_000, "The tide erases the trail."),
            teaser = "A made-up character standing for the crews who carried liquor ashore on Long Island.",
            facts = listOf(
                "1920–1933: Liquor ships wait offshore; fast boats run cases to Long Island beaches at night.",
                "Landing spots included the South Shore and the East End around Montauk and the North Fork.",
                "From the beach, cases went by foot, cart and truck to New York City.",
                "This card is fictional: it honours the unnamed people who did the carrying.",
            ),
            why = "History remembers the bosses. This one is for the people who walked the cargo up the beach.",
        ),
        outlaw(
            "outlaw-sutton", "The Last Moonshiner", "Marvin \"Popcorn\" Sutton · Appalachia, 1946–2009",
            OutlawCard("Popcorn Sutton", VOL_2, Rarity.EPIC, 19_000_000, "The old ways run deep."),
            teaser = "Legacy outlaw: still making mountain moonshine decades after Prohibition ended.",
            facts = listOf(
                "1946: Born in Maggie Valley, North Carolina, into a moonshining family.",
                "Makes whiskey in the Smoky Mountains the old way, and becomes a folk hero on film.",
                "2008: Federal agents find large stills and hundreds of gallons of liquor.",
                "2009: Dies shortly before he was due to report to federal prison.",
            ),
            why = "Legacy card: the trade outlived the law that created it.",
        ),
        outlaw(
            "outlaw-schultz", "The Beer Baron", "Dutch Schultz · The Bronx, New York, 1901–1935",
            OutlawCard("Dutch Schultz", VOL_2, Rarity.LEGENDARY, 20_000_000, "The city never runs dry."),
            teaser = "Ran beer through the Bronx and Harlem, then fought the government and the Mob at once.",
            facts = listOf(
                "1901: Born Arthur Flegenheimer in New York.",
                "1920s: Builds a beer empire in the Bronx, reportedly with operations as far off as the Catskills.",
                "1935: Tried for tax evasion upstate: a hung jury in Syracuse, then acquittal in Malone.",
                "Oct 1935: Shot in Newark by fellow gangsters; dies the next day.",
            ),
            why = "The streets of the Bronx, block by block.",
        ),
        outlaw(
            "outlaw-capone", "The King of Chicago", "Al Capone · Chicago, 1899–1947",
            OutlawCard("Al Capone", VOL_2, Rarity.BOSS, 25_000_000, "The city has a price."),
            teaser = "Boss card. The most notorious bootlegger of all, brought down by his tax returns.",
            facts = listOf(
                "1899: Born in Brooklyn, New York.",
                "1920s: Runs the Chicago Outfit's bootlegging, gambling and brothels.",
                "1929: The St. Valentine's Day Massacre is widely blamed on his gang.",
                "1931: Convicted of tax evasion; sentenced to 11 years, later served partly in Alcatraz.",
                "1947: Dies in Florida.",
            ),
            why = "The boss card: collect everyone else first. Even kings get caught by paperwork.",
        ),
    )
}
