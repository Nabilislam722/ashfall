function useItem(key, released)
    if data.item[key] == "sword" and released ~= true then
        player:swingSword()
    elseif data.item[key] == "boomerang" and released ~= true then
        player:useBoomerang()
    elseif data.item[key] == "bomb" and released ~= true then
        player:useBomb()
    elseif data.item[key] == "bow" and player.state ~= 0 then
        player:useBow() -- adds bow to the buffer
    elseif data.item[key] == "grapple" and released ~= true then
        player:usegrapple()
    elseif data.item[key] == "fire" and released ~= true then
        player:useFire()
    elseif data.item[key] == "staff" and released ~= true then
        staff:press((key == "left" or key == "altL") and "left" or "right")
    end
end
