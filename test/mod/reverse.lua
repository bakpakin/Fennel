local function reverse(ast)
   local l = list()
   for _,x in ipairs(ast) do
      table.insert(l, 1, x)
   end
   return l
end

return {reverse=reverse}
