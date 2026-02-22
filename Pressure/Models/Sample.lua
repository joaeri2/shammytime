local addonName = ...
if addonName ~= "ShammyTime" then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local Models = ShammyTime.PressureModels
if not Models then return end

function Models.CreateSampleModel(ctx)
    local PS = ctx.PS
    local WINDOWS = ctx.WINDOWS
    local NUM_WINDOWS = ctx.NUM_WINDOWS
    local math_max = ctx.math_max

    local model = {}

    function model.Clear()
        PS.pressureSamples = {}
        PS.pressureSampleValues = {}
        PS.pressureSampleHead = 1
        PS.pressureSampleTail = 0
        PS.pressureSampleCount = 0
    end

    function model.Update(now, elapsed, pressureRatio)
        local sampleMaxCount = math_max(PS.pressureSampleMaxCount or 7000, 64)
        local nextTail = (PS.pressureSampleTail or 0) + 1
        if nextTail > sampleMaxCount then
            nextTail = 1
        end
        PS.pressureSampleTail = nextTail
        PS.pressureSamples[nextTail] = now
        PS.pressureSampleValues[nextTail] = pressureRatio
        if (PS.pressureSampleCount or 0) >= sampleMaxCount then
            local newHead = (PS.pressureSampleHead or 1) + 1
            if newHead > sampleMaxCount then
                newHead = 1
            end
            PS.pressureSampleHead = newHead
        else
            PS.pressureSampleCount = (PS.pressureSampleCount or 0) + 1
            if PS.pressureSampleCount == 1 then
                PS.pressureSampleHead = nextTail
            end
        end

        local sampleCutoff = now - PS.pressureSampleRetention
        while (PS.pressureSampleCount or 0) > 0 do
            local headIdx = PS.pressureSampleHead or 1
            local headTime = PS.pressureSamples[headIdx]
            if not headTime or headTime < sampleCutoff then
                PS.pressureSamples[headIdx] = nil
                PS.pressureSampleValues[headIdx] = nil
                local newHead = headIdx + 1
                if newHead > sampleMaxCount then
                    newHead = 1
                end
                PS.pressureSampleHead = newHead
                PS.pressureSampleCount = (PS.pressureSampleCount or 0) - 1
            else
                break
            end
        end
        if (PS.pressureSampleCount or 0) <= 0 then
            PS.pressureSampleHead = 1
            PS.pressureSampleTail = 0
        end

        PS.bucketStatsElapsed = PS.bucketStatsElapsed + elapsed
        if PS.bucketStatsElapsed >= PS.bucketStatsInterval then
            PS.bucketStatsElapsed = 0
            for wi = 1, NUM_WINDOWS do
                PS.pressureBucketAvg[wi] = 0
                PS.pressureBucketMax[wi] = 0
            end
            local bucketCount = { 0, 0, 0, 0, 0 }
            local sampleCount = PS.pressureSampleCount or 0
            local sampleIdx = PS.pressureSampleHead or 1
            for _ = 1, sampleCount do
                local sampleTime = PS.pressureSamples[sampleIdx]
                local samplePressure = PS.pressureSampleValues[sampleIdx]
                if sampleTime and samplePressure then
                    local age = now - sampleTime
                    for wi = 1, NUM_WINDOWS do
                        if age <= WINDOWS[wi] then
                            PS.pressureBucketAvg[wi] = PS.pressureBucketAvg[wi] + samplePressure
                            bucketCount[wi] = bucketCount[wi] + 1
                            if samplePressure > PS.pressureBucketMax[wi] then
                                PS.pressureBucketMax[wi] = samplePressure
                            end
                        end
                    end
                end
                sampleIdx = sampleIdx + 1
                if sampleIdx > sampleMaxCount then
                    sampleIdx = 1
                end
            end
            for wi = 1, NUM_WINDOWS do
                if bucketCount[wi] > 0 then
                    PS.pressureBucketAvg[wi] = PS.pressureBucketAvg[wi] / bucketCount[wi]
                end
            end
        end
    end

    return model
end
